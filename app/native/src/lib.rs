mod file_import;
#[cfg(target_os = "ios")]
mod ios_legacy;
#[cfg(any(target_os = "macos", target_os = "ios"))]
mod macos;
mod player;
mod store;
#[cfg(windows)]
mod windows_media;

use nsh_core::prelude::*;
use player::Player;
use std::{
    path::PathBuf,
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

/// What an import did: photos new to the album, photos it already held, and files Still could not read.
#[derive(Clone, Default, JsObject)]
pub struct Imported {
    pub added: u32,
    pub existing: u32,
    pub skipped: u32,
}

async fn import_selection(
    id: String,
    files: Vec<store::MediaInput>,
    temp: tempfile::TempDir,
) -> Result<Imported, String> {
    blocking(move || {
        let _keep_exports = temp;
        let (counts, paths, videos) = with_store(|s| {
            Ok((
                s.import_media(&id, files)?,
                s.playlist(&id)?,
                s.video_posters(&id)?,
            ))
        })?;
        let mut p = player().lock().unwrap();
        if p.album.as_ref() == Some(&id) {
            p.video_posters = videos.into_iter().collect();
            p.update(paths);
        }
        Ok(counts)
    })
    .await
    .map_err(|e| e.to_string())?
}

async fn prepare_files(
    paths: Vec<PathBuf>,
) -> Result<(Vec<store::MediaInput>, tempfile::TempDir), String> {
    blocking(move || {
        let temp = tempfile::tempdir().map_err(|e| e.to_string())?;
        let files = file_import::inputs(paths, temp.path());
        Ok((files, temp))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn dropped_path(uri: &str) -> PathBuf {
    // `file:///Users/a%20b.jpg`, as the desktops report dropped files.
    let raw = match uri.strip_prefix("file:") {
        Some(rest) => rest.strip_prefix("//").unwrap_or(rest),
        None => uri,
    };
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = (bytes[i] == b'%')
            .then(|| raw.get(i + 1..i + 3))
            .flatten()
            .and_then(|pair| u8::from_str_radix(pair, 16).ok());
        match hex {
            Some(byte) => {
                out.push(byte);
                i += 3;
            }
            None => {
                out.push(bytes[i]);
                i += 1;
            }
        }
    }
    PathBuf::from(local_path(&String::from_utf8_lossy(&out), cfg!(windows)))
}

/// A `file:` URL's path as the system writes it: Windows drops the slash before the drive (`/C:/a` is `C:/a`).
fn local_path(path: &str, windows: bool) -> &str {
    let drive = path.as_bytes();
    let on_drive =
        drive.len() > 2 && drive[0] == b'/' && drive[1].is_ascii_alphabetic() && drive[2] == b':';
    if windows && on_drive {
        &path[1..]
    } else {
        path
    }
}

/// Dropped files as they are, and the images inside dropped folders, in name order.
fn dropped_files(path: PathBuf, depth: u8, out: &mut Vec<PathBuf>) {
    if !path.is_dir() {
        out.push(path);
        return;
    }
    let Ok(entries) = std::fs::read_dir(&path) else {
        return;
    };
    let mut children: Vec<PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
    children.sort();
    for child in children {
        let hidden = child
            .file_name()
            .is_some_and(|name| name.to_string_lossy().starts_with('.'));
        if hidden {
            continue;
        }
        if child.is_dir() {
            if depth > 0 {
                dropped_files(child, depth - 1, out);
            }
        } else if file_import::supported(&child) {
            out.push(child);
        }
    }
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
        #[cfg(target_os = "ios")]
        let (files, temp) = {
            let temp = tempfile::tempdir().map_err(|e| e.to_string())?;
            let (files, skipped) = macos::pick(temp.path()).await?;
            if skipped > 0 {
                return Err("无法读取选中的媒体".into());
            }
            (files, temp)
        };
        #[cfg(not(target_os = "ios"))]
        let (files, temp) = prepare_files(file_import::pick().await?).await?;
        blocking(move || {
            let _keep_exports = temp;
            with_store(|s| s.create_with_media(&name, files))
        })
        .await
        .map_err(|e| e.to_string())?
    }
    pub async fn add_files(id: String) -> Result<Imported, String> {
        let paths = file_import::pick().await?;
        let (files, temp) = prepare_files(paths).await?;
        import_selection(id, files, temp).await
    }
    pub async fn add_dropped(id: String, uris: Vec<String>) -> Result<Imported, String> {
        let paths = blocking(move || {
            let mut paths = Vec::new();
            for uri in &uris {
                dropped_files(dropped_path(uri), 4, &mut paths);
            }
            paths
        })
        .await
        .map_err(|e| e.to_string())?;
        let (files, temp) = prepare_files(paths).await?;
        import_selection(id, files, temp).await
    }
    pub async fn add_apple_photos(id: String) -> Result<Imported, String> {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            let temp = tempfile::tempdir().map_err(|e| e.to_string())?;
            let (selected, skipped) = macos::pick(temp.path()).await?;
            let mut counts = if selected.is_empty() {
                Imported::default()
            } else {
                import_selection(id, selected, temp).await?
            };
            counts.skipped += skipped;
            Ok(counts)
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            let _ = id;
            Err("Apple 照片仅在 Apple 设备上可用".into())
        }
    }
    pub fn play_album(id: String) -> Result<(), String> {
        let (paths, videos, shuffle) =
            with_store(|s| Ok((s.playlist(&id)?, s.video_posters(&id)?, s.shuffle()?)))?;
        let mut p = player().lock().unwrap();
        p.video_posters = videos.into_iter().collect();
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
    pub fn finish_video(poster: String, failed: bool) {
        player().lock().unwrap().finish_video(&poster, failed)
    }
    pub fn previous() {
        player().lock().unwrap().step(-1)
    }
}

#[native_module("contactsheet/native")]
fn native(registry: &mut Registry) {
    registry.module::<Photos>();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dropped_urls_become_paths_and_folders_give_their_images() {
        #[cfg(not(windows))]
        assert_eq!(
            dropped_path("file:///Users/a%20b/%E6%B9%96.jpg"),
            PathBuf::from("/Users/a b/湖.jpg")
        );
        assert_eq!(
            local_path("/C:/Users/a b/湖.jpg", true),
            "C:/Users/a b/湖.jpg"
        );
        assert_eq!(local_path("/Users/a", true), "/Users/a");
        assert_eq!(local_path("/C:/a", false), "/C:/a");
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir(root.path().join("trip")).unwrap();
        for name in [
            "b.PNG",
            "a.jpg",
            "notes.txt",
            ".hidden.jpg",
            "trip/c.heic",
            "trip/d.dng",
        ] {
            std::fs::write(root.path().join(name), b"").unwrap();
        }
        let mut found = Vec::new();
        dropped_files(root.path().to_path_buf(), 4, &mut found);
        let names: Vec<_> = found
            .iter()
            .map(|path| {
                let inside = path.strip_prefix(root.path()).unwrap();
                inside.to_string_lossy().replace('\\', "/")
            })
            .collect();
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        assert_eq!(names, ["a.jpg", "b.PNG", "trip/c.heic", "trip/d.dng"]);
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        assert_eq!(names, ["a.jpg", "b.PNG"]);
        // A file dropped by itself is offered as it is; the importer decides whether it is an image.
        let mut single = Vec::new();
        dropped_files(root.path().join("notes.txt"), 4, &mut single);
        assert_eq!(single.len(), 1);
    }
}
