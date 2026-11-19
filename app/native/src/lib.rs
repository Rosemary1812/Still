#[cfg(target_os = "ios")]
mod ios_legacy;
#[cfg(target_os = "macos")]
mod macos;
mod player;
mod store;

use nsh_core::{
    picker::{PickRequest, PickedFile},
    prelude::*,
};
use player::Player;
use std::{
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};
use store::{Library, Store};
fn with_store<T>(f: impl FnOnce(&mut Store) -> store::Result<T>) -> Result<T, String> {
    let run = || {
        let mut store = Store::open(store::library_root()?)?;
        f(&mut store)
    };
    run().map_err(|e| e.to_string())
}

fn player() -> &'static Mutex<Player> {
    static PLAYER: OnceLock<Mutex<Player>> = OnceLock::new();
    PLAYER.get_or_init(|| {
        std::thread::spawn(|| {
            loop {
                std::thread::sleep(Duration::from_millis(100));
                if let Ok(mut state) = player().lock() {
                    state.tick(Instant::now());
                }
            }
        });
        Mutex::new(Player::default())
    })
}

#[derive(Clone, JsObject)]
pub struct Snapshot {
    pub paths: Vec<String>,
    pub current: Option<String>,
    pub playing: bool,
    pub revision: u32,
    pub shuffle: bool,
}

async fn import_picked(id: String, picked: Vec<PickedFile>) -> Result<(), String> {
    if picked.is_empty() {
        return Ok(());
    }
    blocking(move || {
        let paths = with_store(|s| {
            s.import(&id, picked)?;
            s.playlist(&id)
        })?;
        let mut p = player().lock().unwrap();
        if p.album.as_ref() == Some(&id) {
            p.update(paths);
        }
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[module]
pub struct Photos;
#[module]
impl Photos {
    pub fn library() -> Result<Library, String> {
        with_store(|s| s.library())
    }
    pub fn create_album(name: String) -> Result<String, String> {
        with_store(|s| s.create(&name))
    }
    pub fn rename_album(id: String, name: String) -> Result<(), String> {
        with_store(|s| s.rename(&id, &name))
    }
    pub fn delete_album(id: String) -> Result<(), String> {
        with_store(|s| s.delete(&id))?;
        let mut p = player().lock().unwrap();
        if p.album.as_ref() == Some(&id) {
            p.replace(vec![]);
        }
        Ok(())
    }
    pub fn remove_photo(id: String, photo_id: String) -> Result<(), String> {
        let paths = with_store(|s| {
            s.remove(&id, &photo_id)?;
            s.playlist(&id)
        })?;
        let mut p = player().lock().unwrap();
        if p.album.as_ref() == Some(&id) {
            p.update(paths);
        }
        Ok(())
    }
    pub fn set_cover(id: String, photo_id: String) -> Result<(), String> {
        with_store(|s| s.cover(&id, &photo_id))
    }
    pub fn save_annotation(
        photo_id: String,
        title: String,
        description: String,
        date: String,
        location: String,
    ) -> Result<(), String> {
        with_store(|s| s.annotate(&photo_id, &title, &description, &date, &location))
    }
    pub fn set_view_mode(mode: String) -> Result<(), String> {
        with_store(|s| s.view(&mode))
    }
    pub async fn create_album_from_picker(name: String) -> Result<String, String> {
        let files = pick_images(PickRequest::new(true, 0)).await;
        if files.is_empty() {
            return Ok(String::new());
        }
        blocking(move || with_store(|s| s.create_with_photos(&name, files)))
            .await
            .map_err(|e| e.to_string())?
    }
    pub async fn add_files(id: String) -> Result<(), String> {
        let files = pick_images(PickRequest::new(true, 0)).await;
        import_picked(id, files).await
    }
    pub async fn add_apple_photos(id: String) -> Result<(), String> {
        #[cfg(target_os = "ios")]
        {
            Self::add_files(id).await
        }
        #[cfg(target_os = "macos")]
        {
            let selected = macos::pick().await?;
            if selected.is_empty() {
                return Ok(());
            }
            let files = blocking(move || macos::read_exports(selected))
                .await
                .map_err(|e| e.to_string())??;
            import_picked(id, files).await
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            let _ = id;
            Err("Apple 照片仅在 Apple 设备上可用".into())
        }
    }
    pub fn play_album(id: String) -> Result<(), String> {
        let (paths, shuffle) = with_store(|s| Ok((s.playlist(&id)?, s.shuffle()?)))?;
        let mut p = player().lock().unwrap();
        p.set_shuffle(shuffle);
        p.replace(paths);
        p.album = Some(id);
        Ok(())
    }
    pub fn snapshot() -> Snapshot {
        let p = player().lock().unwrap();
        Snapshot {
            paths: p.paths.clone(),
            current: p.current().cloned(),
            playing: p.playing,
            revision: p.revision,
            shuffle: p.shuffle,
        }
    }
    pub fn set_shuffle(enabled: bool) -> Result<(), String> {
        with_store(|s| s.set_shuffle(enabled))?;
        player().lock().unwrap().set_shuffle(enabled);
        Ok(())
    }
    pub fn toggle() {
        player().lock().unwrap().toggle()
    }
    pub fn next() {
        player().lock().unwrap().step(1)
    }
    pub fn previous() {
        player().lock().unwrap().step(-1)
    }
}

#[native_module("contactsheet/native")]
fn native(registry: &mut Registry) {
    registry.module::<Photos>();
}
