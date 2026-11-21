use nsh_core::prelude::*;
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use std::{
    collections::HashMap,
    env, fs,
    path::{Component, Path, PathBuf},
    time::Duration,
};
use uuid::Uuid;

mod media;
mod movie;
pub use media::MediaInput;
pub type ImportCounts = crate::Imported;

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
    pub kind: String,
    pub video_url: Option<String>,
    pub duration: Option<f64>,
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
        let mut db = Connection::open(root.join("library.sqlite3"))?;
        db.busy_timeout(Duration::from_secs(5))?;
        db.execute_batch("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;")?;
        let migration = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        match migration.pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))? {
            0 => {
                migration.execute_batch(include_str!("../schema.sql"))?;
                migration.execute_batch(include_str!("../media-schema.sql"))?;
            }
            1 => {}
            _ => return Err("图库由更新版本的 Still 创建".into()),
        }
        migration.commit()?;
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
        let mut query = tx.prepare(
            "SELECT p.id,p.path,p.title,p.description,p.date,p.location,
                    COALESCE(m.kind,'photo'),m.motion,m.duration
             FROM photos p LEFT JOIN media_resources m ON m.photo=p.id
             WHERE EXISTS(SELECT 1 FROM members WHERE photo=p.id) ORDER BY p.rowid",
        )?;
        let mut rows = query.query([])?;
        while let Some(row) = rows.next()? {
            let motion: Option<String> = row.get(7)?;
            photos.push(Photo {
                id: row.get(0)?,
                url: Self::url(&self.root, &row.get::<_, String>(1)?)?,
                title: row.get(2)?,
                description: row.get(3)?,
                date: row.get(4)?,
                location: row.get(5)?,
                kind: row.get(6)?,
                video_url: motion.map(|p| Self::url(&self.root, &p)).transpose()?,
                duration: row.get(8)?,
            });
        }
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
    pub fn video_posters(&self, album: &str) -> Result<Vec<String>> {
        self.db
            .prepare(
                "SELECT p.path FROM members a JOIN photos p ON a.photo=p.id
             JOIN media_resources m ON p.id=m.photo WHERE a.album=?1 AND m.kind='video'",
            )?
            .query_map([album], |r| r.get::<_, String>(0))?
            .map(|p| Self::url(&self.root, &p?))
            .collect()
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
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }
    fn image(name: &str) -> MediaInput {
        MediaInput::Photo(fixture(name))
    }
    const FIRST: &[u8] = include_bytes!("../tests/fixtures/first.png");
    #[test]
    fn reopen_managed_shared_photos_in_user_order() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = Store::open(dir.path().to_owned()).unwrap();
        let a = s.create("旅行").unwrap();
        let b = s.create("家庭").unwrap();
        s.import_media(
            &a,
            vec![image("first.png"), image("second.png"), image("first.png")],
        )
        .unwrap();
        s.import_media(&b, vec![image("second.png")]).unwrap();
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
        store
            .import_media(&album, vec![image("first.png")])
            .unwrap();
        let source = store.library().unwrap().photos[0].url.clone();
        assert_eq!(store.playlist(&album).unwrap(), [source.clone()]);
        assert!(source.contains("Application Support"));
        assert_eq!(fs::read(source).unwrap(), FIRST);
    }
    #[test]
    fn creating_album_from_picker_is_all_or_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path().into()).unwrap();
        assert_eq!(store.create_with_media("cancel", vec![]).unwrap(), "");
        assert!(
            store
                .create_with_media("failure", vec![image("first.png"), image("broken.png")])
                .is_err()
        );
        assert!(store.library().unwrap().albums.is_empty());
        let id = store
            .create_with_media("success", vec![image("first.png")])
            .unwrap();
        assert_eq!(store.playlist(&id).unwrap().len(), 1);
        assert!(!store.shuffle().unwrap());
        store.set_shuffle(true).unwrap();
        drop(store);
        assert!(Store::open(dir.path().into()).unwrap().shuffle().unwrap());
    }
    #[test]
    fn invalid_items_are_skipped_and_nonmember_cover_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = Store::open(dir.path().to_owned()).unwrap();
        let a = s.create("A").unwrap();
        let b = s.create("B").unwrap();
        let counts = s
            .import_media(&a, vec![image("first.png"), image("broken.png")])
            .unwrap();
        assert_eq!((counts.added, counts.skipped), (1, 1));
        let photo = s.library().unwrap().photos[0].id.clone();
        assert!(s.cover(&b, &photo).is_err());
        assert!(s.library().unwrap().albums[1].cover_id.is_none());
        assert!(s.rename(&a, "  ").is_err());
        assert!(s.view("bogus").is_err());
        assert!(
            s.import_media("missing", vec![image("second.png")])
                .is_err()
        );
        assert_eq!(s.library().unwrap().photos.len(), 1);
    }
}
