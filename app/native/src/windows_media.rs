use std::{
    fs,
    path::{Path, PathBuf},
};
use windows::{
    Storage::{
        FileProperties::{ThumbnailMode, ThumbnailType},
        StorageFile,
        Streams::DataReader,
    },
    Win32::System::WinRT::{RO_INIT_MULTITHREADED, RoInitialize, RoUninitialize},
    core::HSTRING,
};

// The picker runs on a blocking worker. Only balance successful COM initializations.
struct Apartment;
impl Drop for Apartment {
    fn drop(&mut self) {
        unsafe { RoUninitialize() };
    }
}

pub fn poster(path: &Path, temp: &Path) -> Option<PathBuf> {
    let _apartment = unsafe { RoInitialize(RO_INIT_MULTITHREADED) }
        .ok()
        .map(|_| Apartment);
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path.as_os_str()))
        .ok()?
        .join()
        .ok()?;
    let image = file
        .GetThumbnailAsyncOverloadDefaultOptions(ThumbnailMode::VideosView, 768)
        .ok()?
        .join()
        .ok()?;
    if image.Type().ok()? != ThumbnailType::Image {
        return None;
    }
    let size = u32::try_from(image.Size().ok()?).ok()?;
    if size == 0 || size > 16 * 1024 * 1024 {
        return None;
    }
    let reader = DataReader::CreateDataReader(&image.GetInputStreamAt(0).ok()?).ok()?;
    if reader.LoadAsync(size).ok()?.join().ok()? != size {
        return None;
    }
    let mut bytes = vec![0; size as usize];
    reader.ReadBytes(&mut bytes).ok()?;
    let extension = crate::store::image_extension(&bytes)?;
    let out = temp.join(format!("{}.{}", uuid::Uuid::new_v4(), extension));
    fs::write(&out, bytes).ok()?;
    Some(out)
}
