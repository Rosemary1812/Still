use nsh_core::{picker::PickedFile, prelude::*};
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    env, fs,
    io::{self, Write},
    path::{Component, Path, PathBuf},
    time::Duration,
};
use tempfile::NamedTempFile;
use uuid::Uuid;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
#[derive(Clone, JsObject)]
pub struct Album {
    pub id: String,
    pub name: String,
    pub photo_ids: Vec<String>,
    pub cover_id: Option<String>,
}
#[derive(Clone, JsObject)]
pub struct Photo {
    pub id: String,
    pub url: String,
    pub title: String,
    pub description: String,
    pub date: String,
    pub location: String,
}
#[derive(Clone, JsObject)]
pub struct Library {
    pub albums: Vec<Album>,
    pub photos: Vec<Photo>,
    pub view_mode: String,
}

/// The managed copy's extension, or `None` for bytes Still cannot show on every client.
pub fn image_extension(bytes: &[u8]) -> Option<&'static str> {
    imagesize::blob_size(bytes).ok()?;
    if bytes.starts_with(b"\xff\xd8\xff") {
        Some("jpg")
    } else if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("png")
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some("gif")
    } else if bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP") {
        Some("webp")
    } else {
        None
    }
}
pub fn library_root() -> Result<PathBuf> {
    if let Some(path) = env::var_os("STILL_LIBRARY_DIR").filter(|v| !v.is_empty()) {
        return Ok(std::path::absolute(path)?);
    }
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    let base = PathBuf::from(env::var_os("HOME").ok_or("缺少用户目录 HOME")?)
        .join("Library/Application Support");
    #[cfg(windows)]
    let base = PathBuf::from(env::var_os("LOCALAPPDATA").ok_or("缺少 LOCALAPPDATA")?);
    #[cfg(not(any(target_os = "macos", target_os = "ios", windows)))]
    let base = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .ok_or("缺少用户数据目录")?;
    Ok(base.join("StillNSH"))
}

pub struct Store {
    db: Connection,
    root: PathBuf,
}
impl Store {
    pub fn open(root: PathBuf) -> Result<Self> {
        fs::create_dir_all(root.join("media"))?;
        let db = Connection::open(root.join("library.sqlite3"))?;
        db.busy_timeout(Duration::from_secs(5))?;
        db.execute_batch("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;")?;
        db.execute_batch(include_str!("../schema.sql"))?;
        #[cfg(target_os = "ios")]
        let db = {
            let mut db = db;
            crate::ios_legacy::import(&mut db, &root)?;
            db
        };
        Ok(Self { db, root })
    }
    fn url(root: &Path, relative: &str) -> Result<String> {
        let path = Path::new(relative);
        if relative.is_empty() || !path.components().all(|p| matches!(p, Component::Normal(_))) {
            return Err("无效的媒体路径".into());
        }
        // NSH accepts native absolute paths on desktop and iOS. The pinned iOS
        // loader treats percent escapes in file URLs as literal filename bytes.
        root.join(path)
            .into_os_string()
            .into_string()
            .map_err(|_| "无法生成图片地址".into())
    }
    pub fn library(&mut self) -> Result<Library> {
        let tx = self.db.transaction()?;
        let mut albums=tx.prepare("SELECT a.id,a.name,c.photo FROM albums a LEFT JOIN covers c ON c.album=a.id ORDER BY a.rowid")?.query_map([],|r|Ok(Album{id:r.get(0)?,name:r.get(1)?,photo_ids:Vec::new(),cover_id:r.get(2)?}))?.collect::<rusqlite::Result<Vec<_>>>()?;
        let mut indices = HashMap::new();
        for (i, a) in albums.iter().enumerate() {
            indices.insert(a.id.clone(), i);
        }
        for item in tx
            .prepare("SELECT album,photo FROM members ORDER BY album,position")?
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
        {
            let (a, p) = item?;
            if let Some(i) = indices.get(&a) {
                albums[*i].photo_ids.push(p)
            }
        }
        for album in &mut albums {
            if album.cover_id.is_none() {
                album.cover_id = album.photo_ids.first().cloned();
            }
        }
        let mut photos = Vec::new();
        for item in tx.prepare("SELECT id,path,title,description,date,location FROM photos WHERE EXISTS(SELECT 1 FROM members WHERE photo=photos.id) ORDER BY rowid")?.query_map([],|r|Ok(Photo{id:r.get(0)?,url:r.get(1)?,title:r.get(2)?,description:r.get(3)?,date:r.get(4)?,location:r.get(5)?}))?{let mut p=item?;p.url=Self::url(&self.root,&p.url)?;photos.push(p)}
        let view_mode = tx
            .query_row("SELECT value FROM settings WHERE key='viewMode'", [], |r| {
                r.get(0)
            })
            .optional()?
            .unwrap_or_else(|| "cabinet".into());
        Ok(Library {
            albums,
            photos,
            view_mode,
        })
    }
    fn name(input: &str) -> Result<&str> {
        let name = input.trim();
        if name.is_empty() {
            Err("请输入相册名称".into())
        } else {
            Ok(name)
        }
    }
    fn changed(n: usize) -> Result<()> {
        if n == 0 {
            Err("找不到相册或照片".into())
        } else {
            Ok(())
        }
    }
    pub fn create(&self, name: &str) -> Result<String> {
        let id = Uuid::new_v4().to_string();
        self.db.execute(
            "INSERT INTO albums(id,name) VALUES(?1,?2)",
            params![id, Self::name(name)?],
        )?;
        Ok(id)
    }
    pub fn rename(&self, id: &str, name: &str) -> Result<()> {
        Self::changed(self.db.execute(
            "UPDATE albums SET name=?2 WHERE id=?1",
            params![id, Self::name(name)?],
        )?)
    }
    pub fn delete(&self, id: &str) -> Result<()> {
        Self::changed(self.db.execute("DELETE FROM albums WHERE id=?1", [id])?)
    }
    pub fn cover(&self, id: &str, photo: &str) -> Result<()> {
        self.db.execute("INSERT INTO covers(album,photo) VALUES(?1,?2) ON CONFLICT(album) DO UPDATE SET photo=excluded.photo",params![id,photo])?;
        Ok(())
    }
    pub fn remove(&self, id: &str, photo: &str) -> Result<()> {
        Self::changed(self.db.execute(
            "DELETE FROM members WHERE album=?1 AND photo=?2",
            params![id, photo],
        )?)
    }
    pub fn annotate(
        &self,
        id: &str,
        title: &str,
        description: &str,
        date: &str,
        location: &str,
    ) -> Result<()> {
        Self::changed(self.db.execute(
            "UPDATE photos SET title=?2,description=?3,date=?4,location=?5 WHERE id=?1",
            params![id, title, description, date, location],
        )?)
    }
    pub fn view(&self, mode: &str) -> Result<()> {
        if !matches!(mode, "cabinet" | "wall") {
            return Err("未知的展示视图".into());
        }
        self.db.execute("INSERT INTO settings(key,value) VALUES('viewMode',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",[mode])?;
        Ok(())
    }
    pub fn playlist(&self, id: &str) -> Result<Vec<String>> {
        self.db
            .query_row("SELECT 1 FROM albums WHERE id=?1", [id], |_| Ok(()))?;
        self.db.prepare("SELECT p.path FROM photos p JOIN members m ON m.photo=p.id WHERE m.album=?1 ORDER BY position")?.query_map([id],|r|r.get::<_,String>(0))?.map(|row|Self::url(&self.root,&row?)).collect()
    }
    pub fn shuffle(&self) -> Result<bool> {
        Ok(self
            .db
            .query_row("SELECT value FROM settings WHERE key='shuffle'", [], |r| {
                r.get::<_, String>(0)
            })
            .optional()?
            .as_deref()
            == Some("1"))
    }
    pub fn set_shuffle(&self, enabled: bool) -> Result<()> {
        self.db.execute("INSERT INTO settings(key,value) VALUES('shuffle',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",[if enabled {"1"} else {"0"}])?;
        Ok(())
    }
    pub fn create_with_photos(&mut self, name: &str, files: Vec<PickedFile>) -> Result<String> {
        if files.is_empty() {
            return Ok(String::new());
        }
        let id = Uuid::new_v4().to_string();
        self.import_batch(&id, Some(Self::name(name)?), files)?;
        Ok(id)
    }
    pub fn import(&mut self, album: &str, files: Vec<PickedFile>) -> Result<()> {
        self.import_batch(album, None, files)
    }
    fn import_batch(
        &mut self,
        album: &str,
        new_name: Option<&str>,
        files: Vec<PickedFile>,
    ) -> Result<()> {
        // Every photo is installed before the transaction can make its membership visible.
        // Content names make crash leftovers harmless and reusable on retry.
        let prepared = files
            .into_iter()
            .map(|file| {
                let bytes = file.data.bytes();
                let Some(ext) = image_extension(bytes) else {
                    return Err(format!("无法读取图片：{}", file.name).into());
                };
                Ok((format!("{:x}", Sha256::digest(bytes)), ext, file))
            })
            .collect::<Result<Vec<_>>>()?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        if let Some(name) = new_name {
            tx.execute("INSERT INTO albums(id,name) VALUES(?1,?2)", [album, name])?;
        } else {
            tx.query_row("SELECT 1 FROM albums WHERE id=?1", [album], |_| Ok(()))?;
        }
        for (digest, ext, file) in prepared {
            let bytes = file.data.bytes();
            let (id, relative) = match tx
                .query_row(
                    "SELECT id,path FROM photos WHERE digest=?1",
                    [&digest],
                    |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
                )
                .optional()?
            {
                Some(row) => row,
                None => {
                    let id = Uuid::new_v4().to_string();
                    let relative = format!("media/{digest}.{ext}");
                    tx.execute(
                        "INSERT INTO photos(id,path,digest) VALUES(?1,?2,?3)",
                        params![id, relative, digest],
                    )?;
                    (id, relative)
                }
            };
            Self::url(&self.root, &relative)?;
            let target = self.root.join(relative);
            if !target.exists() {
                let parent = target.parent().ok_or("无效的媒体路径")?;
                fs::create_dir_all(parent)?;
                let mut tmp = NamedTempFile::new_in(parent)?;
                tmp.write_all(bytes)?;
                tmp.as_file().sync_all()?;
                if let Err(e) = tmp.persist_noclobber(&target) {
                    if e.error.kind() != io::ErrorKind::AlreadyExists {
                        return Err(e.into());
                    }
                }
                #[cfg(unix)]
                fs::File::open(parent)?.sync_all()?;
            }
            tx.execute("INSERT INTO members(album,photo,position) SELECT ?1,?2,COALESCE(MAX(position),-1)+1 FROM members WHERE album=?1 ON CONFLICT(album,photo) DO NOTHING",params![album,id])?;
        }
        tx.commit()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_core::ImageData;
    fn image(name: &str, bytes: &'static [u8]) -> PickedFile {
        PickedFile::new(name, "image/png", ImageData::new(bytes))
    }
    const FIRST: &[u8] = include_bytes!("../tests/fixtures/first.png");
    const SECOND: &[u8] = include_bytes!("../tests/fixtures/second.png");
    #[test]
    fn reopen_managed_shared_photos_in_user_order() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = Store::open(dir.path().to_owned()).unwrap();
        let a = s.create("旅行").unwrap();
        let b = s.create("家庭").unwrap();
        s.import(
            &a,
            vec![
                image("a.png", FIRST),
                image("b.png", SECOND),
                image("another-name.png", FIRST),
            ],
        )
        .unwrap();
        s.import(&b, vec![image("renamed.png", SECOND)]).unwrap();
        let l = s.library().unwrap();
        let ids = l.albums[0].photo_ids.clone();
        assert_eq!(ids.len(), 2);
        assert_eq!(l.photos.len(), 2);
        assert_eq!(l.albums[1].photo_ids, vec![ids[1].clone()]);
        s.cover(&a, &ids[1]).unwrap();
        s.annotate(&ids[1], "海边", "日落", "2026-10-01", "上海")
            .unwrap();
        s.view("wall").unwrap();
        drop(s);
        let mut s = Store::open(dir.path().to_owned()).unwrap();
        let l = s.library().unwrap();
        assert_eq!(l.view_mode, "wall");
        assert_eq!(l.albums[0].cover_id.as_ref(), Some(&ids[1]));
        assert_eq!(l.albums[0].photo_ids, ids);
        let paths = s.playlist(&a).unwrap();
        let path = Path::new(&paths[0]);
        assert!(path.starts_with(dir.path().join("media")));
        assert_eq!(fs::read(path).unwrap(), FIRST);
        s.remove(&a, &ids[1]).unwrap();
        assert_eq!(
            s.library().unwrap().albums[0].cover_id.as_ref(),
            Some(&ids[0])
        );
        s.delete(&a).unwrap();
        let l = s.library().unwrap();
        assert_eq!(l.albums.len(), 1);
        assert_eq!(l.photos.len(), 1);
        let p = &l.photos[0];
        assert_eq!(
            (&*p.title, &*p.description, &*p.date, &*p.location),
            ("海边", "日落", "2026-10-01", "上海")
        );
    }
    #[test]
    fn image_source_preserves_spaces_and_non_ascii_for_nsh() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("Application Support/Still #相册");
        let mut store = Store::open(root).unwrap();
        let album = store.create("Still").unwrap();
        store.import(&album, vec![image("one", FIRST)]).unwrap();
        let source = store.library().unwrap().photos[0].url.clone();
        assert_eq!(store.playlist(&album).unwrap(), [source.clone()]);
        assert!(source.contains("Application Support"));
        assert_eq!(fs::read(source).unwrap(), FIRST);
    }
    #[test]
    fn creating_album_from_picker_is_all_or_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path().into()).unwrap();
        assert_eq!(store.create_with_photos("cancel", vec![]).unwrap(), "");
        assert!(
            store
                .create_with_photos("failure", vec![image("ok", FIRST), image("broken", b"GIF")])
                .is_err()
        );
        assert!(store.library().unwrap().albums.is_empty());
        let id = store
            .create_with_photos("success", vec![image("ok", FIRST)])
            .unwrap();
        assert_eq!(store.playlist(&id).unwrap().len(), 1);
        assert!(!store.shuffle().unwrap());
        store.set_shuffle(true).unwrap();
        drop(store);
        assert!(Store::open(dir.path().into()).unwrap().shuffle().unwrap());
    }
    #[test]
    fn invalid_batch_and_nonmember_cover_make_no_visible_changes() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = Store::open(dir.path().to_owned()).unwrap();
        let a = s.create("A").unwrap();
        let b = s.create("B").unwrap();
        assert!(
            s.import(&a, vec![image("ok", FIRST), image("broken", b"GIF89a")])
                .is_err()
        );
        assert_eq!(fs::read_dir(dir.path().join("media")).unwrap().count(), 0);
        assert!(s.library().unwrap().photos.is_empty());
        s.import(&a, vec![image("ok", FIRST)]).unwrap();
        let photo = s.library().unwrap().photos[0].id.clone();
        assert!(s.cover(&b, &photo).is_err());
        assert!(s.library().unwrap().albums[1].cover_id.is_none());
        assert!(s.rename(&a, "  ").is_err());
        assert!(s.view("bogus").is_err());
        assert!(s.import("missing", vec![image("b", SECOND)]).is_err());
        assert_eq!(s.library().unwrap().photos.len(), 1);
    }
}
