use nsh_core::{ImageData, picker::PickedFile};
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
    fn contactsheet_choose_photo(context: *mut c_void, reply: Reply);
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
type Selection = Result<Vec<PathBuf>, String>;
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
pub async fn pick() -> Selection {
    let (sender, receiver) = mpsc::channel();
    unsafe {
        contactsheet_choose_photo(Box::into_raw(Box::new(sender)).cast(), reply);
    }
    loop {
        match receiver.try_recv() {
            Ok(result) => return result,
            Err(mpsc::TryRecvError::Disconnected) => return Err("照片选择器已关闭".into()),
            Err(mpsc::TryRecvError::Empty) => {
                nsh_core::prelude::timer(Duration::from_millis(50)).await
            }
        }
    }
}
pub fn read_exports(paths: Vec<PathBuf>) -> Result<Vec<PickedFile>, String> {
    let result = paths
        .iter()
        .map(|path| {
            let data = fs::read(path).map_err(|e| e.to_string())?;
            Ok(PickedFile::new(
                "Photo.jpg",
                "image/jpeg",
                ImageData::new(data),
            ))
        })
        .collect();
    for path in paths {
        let _ = fs::remove_file(path);
    }
    result
}
