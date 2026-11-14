use std::time::{Duration, Instant};

#[derive(Default)]
pub struct Player {
    pub paths: Vec<String>,
    index: usize,
    pub playing: bool,
    deadline: Option<Instant>,
    pub revision: u32,
}
impl Player {
    pub fn current(&self) -> Option<&String> { self.paths.get(self.index) }
    pub fn replace(&mut self, paths: Vec<String>) {
        self.paths = paths; self.index = 0; self.playing = false;
        self.deadline = None; self.revision += 1;
    }
    pub fn toggle(&mut self) {
        self.playing = !self.playing && !self.paths.is_empty();
        self.reset();
    }
    fn reset(&mut self) {
        self.deadline = (self.playing && self.paths.len() > 1).then(|| Instant::now() + Duration::from_secs(5));
        self.revision += 1;
    }
    pub fn step(&mut self, direction: isize) {
        if self.paths.is_empty() { return; }
        self.index = (self.index as isize + direction).rem_euclid(self.paths.len() as isize) as usize;
        self.reset();
    }
    pub fn tick(&mut self, now: Instant) {
        if self.deadline.is_some_and(|deadline| now >= deadline) { self.step(1); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pause_cancels_deadline_and_replace_resets_playback() {
        let mut p = Player::default();
        p.replace(vec!["a".into(), "b".into()]); p.toggle();
        p.tick(Instant::now() + Duration::from_secs(6));
        assert_eq!(p.current().map(String::as_str), Some("b"));
        p.toggle(); p.tick(Instant::now() + Duration::from_secs(60));
        assert_eq!(p.current().map(String::as_str), Some("b"));
        p.replace(vec![]); p.toggle(); p.step(-1);
        assert!(!p.playing); assert!(p.current().is_none());
    }
    #[test]
    fn previous_wraps_and_single_image_never_schedules() {
        let mut p = Player::default();
        p.replace(vec!["a".into(), "b".into()]); p.step(-1);
        assert_eq!(p.current().map(String::as_str), Some("b"));
        p.replace(vec!["only".into()]); p.toggle();
        assert!(p.deadline.is_none());
    }
}
