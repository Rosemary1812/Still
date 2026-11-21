use crate::store::MediaInput;
use nsh_core::{
    file_dialog::{FileFilter, OpenDialog},
    prelude::pick_paths,
};
use std::path::{Path, PathBuf};

const PHOTOS: &[&str] = &["jpg", "jpeg", "jpe", "png", "gif", "webp"];
const APPLE_PHOTOS: &[&str] = &[
    "heic", "heif", "avif", "tif", "tiff", "bmp", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf",
    "rw2", "pef", "srw",
];
const MOVIES: &[&str] = &["mp4", "mov", "m4v"];

fn extensions() -> impl Iterator<Item = &'static str> {
    PHOTOS
        .iter()
        .chain(
            APPLE_PHOTOS
                .iter()
                .filter(|_| cfg!(any(target_os = "macos", target_os = "ios"))),
        )
        .chain(MOVIES)
        .copied()
}
fn extension(path: &Path) -> String {
    path.extension()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
}
pub fn supported(path: &Path) -> bool {
    extensions().any(|e| e == extension(path))
}

pub async fn pick() -> Result<Vec<PathBuf>, String> {
    Ok(pick_paths(
        OpenDialog::files()
            .multiple(true)
            .filter(FileFilter::new("照片和视频", extensions())),
    )
    .await?
    .unwrap_or_default())
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn jpeg(path: &Path, temp: &Path) -> Option<PathBuf> {
    let bytes = crate::macos::export_jpeg(path)?;
    let out = temp.join(format!("{}.jpg", uuid::Uuid::new_v4()));
    std::fs::write(&out, bytes).ok()?;
    Some(out)
}

pub fn inputs(paths: Vec<PathBuf>, temp: &Path) -> Vec<MediaInput> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    let pairs = live_pairs(&paths);
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    let _ = temp;
    let mut inputs = Vec::new();
    for (index, path) in paths.iter().enumerate() {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        if let Some(&(still, motion)) = pairs.get(&index) {
            if index == still.min(motion) {
                let still = paths[still].clone();
                let poster = APPLE_PHOTOS
                    .contains(&extension(&still).as_str())
                    .then(|| jpeg(&still, temp))
                    .flatten();
                inputs.push(MediaInput::Live {
                    still,
                    motion: paths[motion].clone(),
                    poster,
                    duration: None,
                });
            }
            continue;
        }
        let _ = index;
        let ext = extension(path);
        if MOVIES.contains(&ext.as_str()) {
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            let item = crate::macos::video_input(path.clone(), temp);
            #[cfg(not(any(target_os = "macos", target_os = "ios")))]
            let item = MediaInput::Video {
                file: path.clone(),
                duration: None,
                #[cfg(windows)]
                poster: crate::windows_media::poster(path, temp),
                #[cfg(not(windows))]
                poster: None,
            };
            inputs.push(item);
        } else {
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            let path = APPLE_PHOTOS
                .contains(&ext.as_str())
                .then(|| jpeg(path, temp))
                .flatten()
                .unwrap_or_else(|| path.clone());
            inputs.push(MediaInput::Photo(path.to_owned()));
        }
    }
    inputs
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn live_pairs(paths: &[PathBuf]) -> std::collections::HashMap<usize, (usize, usize)> {
    use std::collections::HashMap;
    let mut groups: HashMap<String, (Vec<usize>, Vec<usize>)> = HashMap::new();
    if !paths
        .iter()
        .any(|p| MOVIES.contains(&extension(p).as_str()))
    {
        return HashMap::new();
    }
    for (index, path) in paths.iter().enumerate() {
        let ext = extension(path);
        if !matches!(
            ext.as_str(),
            "jpg" | "jpeg" | "heic" | "heif" | "mov" | "mp4" | "m4v"
        ) {
            continue;
        }
        if let Some(id) = crate::macos::live_identifier(path) {
            let (stills, movies) = groups.entry(id).or_default();
            if MOVIES.contains(&ext.as_str()) {
                movies.push(index)
            } else {
                stills.push(index)
            }
        }
    }
    let mut pairs = HashMap::new();
    for (stills, movies) in groups.values() {
        if let ([still], [movie]) = (&stills[..], &movies[..]) {
            pairs.insert(*still, (*still, *movie));
            pairs.insert(*movie, (*still, *movie));
        }
    }
    pairs
}
