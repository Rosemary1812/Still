use std::time::{Duration, Instant};

#[derive(Default)]
pub struct Player {
    pub album: Option<String>,
    pub paths: Vec<String>,
    index: usize,
    pub playing: bool,
    pub shuffle: bool,
    remaining: Vec<String>,
    history: Vec<String>,
    deadline: Option<Instant>,
    pub revision: u32,
}
impl Player {
    pub fn current(&self) -> Option<&String> {
        self.paths.get(self.index)
    }
    pub fn replace(&mut self, paths: Vec<String>) {
        self.album = None;
        self.paths = paths;
        self.index = 0;
        self.playing = !self.paths.is_empty();
        self.remaining.clear();
        self.history.clear();
        self.reset();
    }
    pub fn set_shuffle(&mut self, enabled: bool) {
        self.shuffle = enabled;
        self.remaining.clear();
        self.history.clear();
        self.revision += 1;
    }
    pub fn update(&mut self, paths: Vec<String>) {
        let index = self
            .current()
            .and_then(|current| paths.iter().position(|p| p == current))
            .unwrap_or(0);
        self.remaining.retain(|p| paths.contains(p));
        self.history.retain(|p| paths.contains(p));
        self.paths = paths;
        self.index = index;
        if self.paths.is_empty() {
            self.playing = false;
        }
        self.reset();
    }
    pub fn toggle(&mut self) {
        self.playing = !self.playing && !self.paths.is_empty();
        self.reset();
    }
    fn reset(&mut self) {
        self.deadline = (self.playing && self.paths.len() > 1)
            .then(|| Instant::now() + Duration::from_secs(60));
        self.revision += 1;
    }
    pub fn step(&mut self, direction: isize) {
        if self.paths.is_empty() {
            return;
        }
        let current = &self.paths[self.index];
        let selected = if self.shuffle && direction > 0 {
            if self.remaining.is_empty() {
                self.remaining
                    .extend(self.paths.iter().filter(|p| *p != current).cloned());
                fastrand::shuffle(&mut self.remaining);
            }
            if self.history.len() == 1000 {
                self.history.remove(0);
            }
            self.history.push(current.clone());
            self.remaining.pop()
        } else if self.shuffle && direction < 0 {
            self.history.pop().inspect(|previous| {
                if previous != current {
                    self.remaining.retain(|p| p != current);
                    self.remaining.push(current.clone());
                }
            })
        } else {
            None
        };
        self.index = selected
            .and_then(|p| self.paths.iter().position(|path| path == &p))
            .unwrap_or_else(|| {
                (self.index as isize + direction).rem_euclid(self.paths.len() as isize) as usize
            });
        self.reset();
    }
    pub fn tick(&mut self, now: Instant) {
        if self.deadline.is_some_and(|deadline| now >= deadline) {
            self.step(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pause_cancels_deadline_and_replace_resets_playback() {
        let mut p = Player::default();
        p.replace(vec!["a".into(), "b".into()]);
        assert!(p.playing);
        p.tick(Instant::now() + Duration::from_secs(59));
        assert_eq!(p.current().map(String::as_str), Some("a"));
        p.tick(Instant::now() + Duration::from_secs(61));
        assert_eq!(p.current().map(String::as_str), Some("b"));
        p.toggle();
        p.tick(Instant::now() + Duration::from_secs(60));
        assert_eq!(p.current().map(String::as_str), Some("b"));
        p.replace(vec![]);
        p.toggle();
        p.step(-1);
        assert!(!p.playing);
        assert!(p.current().is_none());
    }
    #[test]
    fn shuffle_covers_cycle_and_previous_retraces_history() {
        let mut p = Player::default();
        p.replace(vec!["a".into(), "b".into(), "c".into()]);
        p.set_shuffle(true);
        let first = p.current().cloned().unwrap();
        p.step(1);
        let second = p.current().cloned().unwrap();
        p.step(1);
        let third = p.current().cloned().unwrap();
        assert_ne!(first, second);
        assert_ne!(first, third);
        assert_ne!(second, third);
        p.step(-1);
        assert_eq!(p.current(), Some(&second));
        p.step(1);
        assert_eq!(p.current(), Some(&third));
    }
    #[test]
    fn previous_wraps_and_single_image_never_schedules() {
        let mut p = Player::default();
        p.replace(vec!["a".into(), "b".into()]);
        p.step(-1);
        assert_eq!(p.current().map(String::as_str), Some("b"));
        p.replace(vec!["only".into()]);
        assert!(p.playing);
        assert!(p.deadline.is_none());
    }
}
