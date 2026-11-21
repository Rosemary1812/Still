use crate::store::MediaInput;
use serde::Deserialize;
use std::{
    ffi::{CStr, CString, c_char, c_void},
    fs,
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
    sync::mpsc,
    time::Duration,
};
type Reply = unsafe extern "C" fn(*const c_char, *const c_char, *mut c_void);
unsafe extern "C" {
    fn contactsheet_live_identifier(source: *const c_char) -> *mut c_char;
    fn contactsheet_free_identifier(id: *mut c_char);
    fn contactsheet_video_info(source: *const c_char, poster: *const c_char) -> f64;
    fn contactsheet_choose_photo(directory: *const c_char, context: *mut c_void, reply: Reply);
    fn contactsheet_export_image(source: *const c_char, destination: *const c_char) -> bool;
}
/// The image at `path` as JPEG bytes, for formats only Apple's decoders read (HEIC, TIFF, RAW).
pub fn export_jpeg(path: &Path) -> Option<Vec<u8>> {
    let out = tempfile::Builder::new()
        .prefix("still-drop-")
        .tempdir()
        .ok()?;
    let target = out.path().join("photo.jpg");
    let source = CString::new(path.as_os_str().as_bytes()).ok()?;
    let destination = CString::new(target.as_os_str().as_bytes()).ok()?;
    unsafe { contactsheet_export_image(source.as_ptr(), destination.as_ptr()) }
        .then(|| fs::read(&target).ok())
        .flatten()
}
#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
enum Export {
    Photo {
        file: PathBuf,
    },
    Video {
        file: PathBuf,
        poster: Option<PathBuf>,
        duration: Option<f64>,
    },
    Live {
        file: PathBuf,
        motion: PathBuf,
        poster: Option<PathBuf>,
        duration: Option<f64>,
    },
}
#[derive(Deserialize)]
struct Batch {
    files: Vec<Export>,
    skipped: u32,
}
type Selection = Result<Batch, String>;
unsafe extern "C" fn reply(json: *const c_char, error: *const c_char, context: *mut c_void) {
    // The presenter calls back exactly once. Strings are only borrowed during the call.
    let sender = unsafe { Box::from_raw(context.cast::<mpsc::Sender<Selection>>()) };
    let value = if !json.is_null() {
        serde_json::from_slice(unsafe { CStr::from_ptr(json) }.to_bytes())
            .map_err(|e| e.to_string())
    } else if !error.is_null() {
        Err(unsafe { CStr::from_ptr(error) }
            .to_string_lossy()
            .into_owned())
    } else {
        Err("照片选择器没有返回结果".into())
    };
    let _ = sender.send(value);
}
pub async fn pick(temp: &Path) -> Result<(Vec<MediaInput>, u32), String> {
    let directory = CString::new(temp.as_os_str().as_bytes()).map_err(|e| e.to_string())?;
    let (sender, receiver) = mpsc::channel::<Selection>();
    unsafe {
        contactsheet_choose_photo(
            directory.as_ptr(),
            Box::into_raw(Box::new(sender)).cast(),
            reply,
        );
    }
    loop {
        match receiver.try_recv() {
            Ok(result) => {
                let batch = result?;
                let files = batch
                    .files
                    .into_iter()
                    .map(|item| match item {
                        Export::Photo { file } => MediaInput::Photo(file),
                        Export::Video {
                            file,
                            poster,
                            duration,
                        } => MediaInput::Video {
                            file,
                            poster,
                            duration,
                        },
                        Export::Live {
                            file,
                            motion,
                            poster,
                            duration,
                        } => MediaInput::Live {
                            still: file,
                            motion,
                            poster,
                            duration,
                        },
                    })
                    .collect();
                return Ok((files, batch.skipped));
            }
            Err(mpsc::TryRecvError::Disconnected) => return Err("照片选择器已关闭".into()),
            Err(mpsc::TryRecvError::Empty) => {
                nsh_core::prelude::timer(Duration::from_millis(50)).await
            }
        }
    }
}
pub fn video_input(file: PathBuf, temp: &Path) -> MediaInput {
    let poster = temp.join(format!("{}.jpg", uuid::Uuid::new_v4()));
    let duration = CString::new(file.as_os_str().as_bytes())
        .ok()
        .and_then(|source| {
            let destination = CString::new(poster.as_os_str().as_bytes()).ok()?;
            let seconds = unsafe { contactsheet_video_info(source.as_ptr(), destination.as_ptr()) };
            (seconds.is_finite() && seconds > 0.0).then_some(seconds)
        });
    MediaInput::Video {
        file,
        poster: poster.is_file().then_some(poster),
        duration,
    }
}

pub fn live_identifier(path: &Path) -> Option<String> {
    let path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let raw = unsafe { contactsheet_live_identifier(path.as_ptr()) };
    if raw.is_null() {
        return None;
    }
    let id = unsafe { CStr::from_ptr(raw) }
        .to_str()
        .ok()
        .map(str::to_owned);
    unsafe { contactsheet_free_identifier(raw) };
    id
}
