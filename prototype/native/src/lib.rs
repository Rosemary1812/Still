mod player;
#[cfg(target_os = "macos")]
mod macos;
use std::{path::PathBuf, sync::{Mutex, OnceLock}, time::Duration};
use nsh_core::{prelude::*, file_dialog::{FileFilter, OpenDialog}};
use player::Player;

fn player() -> &'static Mutex<Player> {
    static PLAYER: OnceLock<Mutex<Player>> = OnceLock::new();
    PLAYER.get_or_init(|| {
        std::thread::spawn(|| loop {
            std::thread::sleep(Duration::from_millis(100));
            if let Ok(mut state) = player().lock() { state.tick(std::time::Instant::now()); }
        });
        Mutex::new(Player::default())
    })
}

/// A snapshot shared by all windows.
#[derive(Clone, JsObject)]
pub struct Snapshot {
    pub paths: Vec<String>,
    pub current: Option<String>,
    pub playing: bool,
    pub revision: u32,
}

/// The single application player and native file picker.
#[module]
pub struct Photos;
#[module]
impl Photos {
    /// Read the Rust player's current state.
    pub fn snapshot() -> Snapshot {
        let state = player().lock().unwrap();
        Snapshot { paths: state.paths.clone(), current: state.current().cloned(), playing: state.playing, revision: state.revision }
    }
    /// Replace the playlist with bundled sample resources.
    pub fn samples(paths: Vec<String>) { player().lock().unwrap().replace(paths); }
    /// Choose local JPEG or PNG files without modifying the originals.
    pub async fn choose() -> Result<(), String> {
        let paths = pick_paths(OpenDialog::files().multiple(true).filter(FileFilter::new("Images", ["jpg", "jpeg", "png"]))).await?;
        if let Some(paths) = paths { Self::load_paths(paths)?; }
        Ok(())
    }
    /// Load the latest readable Apple Photos image after explicit authorization.
    pub async fn apple_photo() -> Result<(), String> {
        #[cfg(target_os = "macos")]
        { Self::load_paths(vec![PathBuf::from(macos::latest().await?)]) }
        #[cfg(not(target_os = "macos"))]
        { Err("Apple Photos is available on macOS only".into()) }
    }
    /// Toggle the single native playback timer.
    pub fn toggle() { player().lock().unwrap().toggle(); }
    /// Advance to the next image.
    pub fn next() { player().lock().unwrap().step(1); }
    /// Return to the previous image.
    pub fn previous() { player().lock().unwrap().step(-1); }
}
impl Photos {
    fn load_paths(paths: Vec<PathBuf>) -> Result<(), String> {
        let urls = paths.into_iter().map(|path| url::Url::from_file_path(&path).map(|u| u.to_string()).map_err(|_| format!("Invalid image path: {}", path.display()))).collect::<Result<Vec<_>, _>>()?;
        player().lock().unwrap().replace(urls);
        Ok(())
    }
}

#[native_module("contactsheet/native")]
fn native(registry: &mut Registry) { registry.module::<Photos>(); }
