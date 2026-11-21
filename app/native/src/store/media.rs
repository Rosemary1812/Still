use super::{ImportCounts, Result, Store, movie};
use rusqlite::{OptionalExtension, TransactionBehavior, params};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{self, Read, Seek, Write},
    path::{Path, PathBuf},
};
use tempfile::NamedTempFile;
use uuid::Uuid;

pub enum MediaInput {
    Photo(PathBuf),
    Video {
        file: PathBuf,
        poster: Option<PathBuf>,
        duration: Option<f64>,
    },
    Live {
        still: PathBuf,
        motion: PathBuf,
        poster: Option<PathBuf>,
        duration: Option<f64>,
    },
}

struct Resource {
    source: File,
    extension: &'static str,
}

fn image(path: &Path, allow_heif: bool) -> io::Result<Resource> {
    let mut source = File::open(path)?;
    let mut head = [0; 12];
    source.read_exact(&mut head)?;
    let extension = if head.starts_with(b"\xff\xd8\xff") {
        "jpg"
    } else if head.starts_with(b"\x89PNG\r\n\x1a\n") {
        "png"
    } else if head.starts_with(b"GIF87a") || head.starts_with(b"GIF89a") {
        "gif"
    } else if head.starts_with(b"RIFF") && &head[8..] == b"WEBP" {
        "webp"
    } else if allow_heif && &head[4..8] == b"ftyp" {
        "heic"
    } else {
        return Err(io::ErrorKind::InvalidData.into());
    };
    source.rewind()?;
    imagesize::reader_size(io::BufReader::new(&mut source)).map_err(io::Error::other)?;
    source.rewind()?;
    Ok(Resource { source, extension })
}

fn video(path: &Path) -> io::Result<(Resource, Option<f64>)> {
    let mut source = File::open(path)?;
    let duration = movie::inspect(&mut source)?;
    source.rewind()?;
    let extension = if path
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("mov"))
    {
        "mov"
    } else {
        "mp4"
    };
    Ok((Resource { source, extension }, duration))
}

struct Validated {
    still: Option<Resource>,
    motion: Option<Resource>,
    poster: Option<Resource>,
    duration: Option<f64>,
}

impl MediaInput {
    fn validate(self) -> io::Result<Validated> {
        match self {
            Self::Photo(path) => Ok(Validated {
                still: Some(image(&path, false)?),
                motion: None,
                poster: None,
                duration: None,
            }),
            Self::Video {
                file,
                poster,
                duration,
            } => {
                let (motion, measured) = video(&file)?;
                Ok(Validated {
                    still: None,
                    motion: Some(motion),
                    poster: poster.and_then(|p| image(&p, false).ok()),
                    duration: valid_duration(duration).or(measured),
                })
            }
            Self::Live {
                still,
                motion,
                poster,
                duration,
            } => {
                let (motion, measured) = video(&motion)?;
                let poster = poster.as_ref().map(|p| image(p, false)).transpose()?;
                Ok(Validated {
                    still: Some(image(&still, poster.is_some())?),
                    motion: Some(motion),
                    poster,
                    duration: valid_duration(duration).or(measured),
                })
            }
        }
    }
}

fn valid_duration(seconds: Option<f64>) -> Option<f64> {
    seconds.filter(|d| d.is_finite() && *d > 0.0)
}

struct Staged {
    file: NamedTempFile,
    digest: String,
    ext: &'static str,
}
impl Staged {
    fn copy(dir: &Path, source: &mut impl Read, ext: &'static str) -> Result<Self> {
        let mut file = NamedTempFile::new_in(dir)?;
        let mut hash = Sha256::new();
        let mut buffer = [0; 64 * 1024];
        loop {
            let count = source.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            hash.update(&buffer[..count]);
            file.write_all(&buffer[..count])?;
        }
        Ok(Self {
            file,
            digest: format!("{:x}", hash.finalize()),
            ext,
        })
    }

    fn resource(dir: &Path, mut resource: Resource) -> Result<Self> {
        Self::copy(dir, &mut resource.source, resource.extension)
    }

    fn path(&self) -> String {
        format!("media/{}.{}", self.digest, self.ext)
    }

    fn install(self, root: &Path, relative: &str) -> Result<()> {
        Store::url(root, relative)?;
        let path = root.join(relative);
        if path.is_file() {
            return Ok(());
        }
        fs::create_dir_all(path.parent().ok_or("无效媒体路径")?)?;
        self.file.as_file().sync_all()?;
        if let Err(e) = self.file.persist_noclobber(&path) {
            if e.error.kind() != io::ErrorKind::AlreadyExists {
                return Err(e.into());
            }
        }
        #[cfg(unix)]
        File::open(path.parent().unwrap())?.sync_all()?;
        Ok(())
    }
}

struct Prepared {
    digest: String,
    preview: String,
    motion: Option<String>,
    original_still: Option<String>,
    duration: Option<f64>,
}

impl Validated {
    fn stage(self, root: &Path) -> Result<Prepared> {
        let dir = root.join("media");
        let still = self.still.map(|s| Staged::resource(&dir, s)).transpose()?;
        let Some(motion) = self.motion else {
            let still = still.expect("photo validation requires a still image");
            let digest = still.digest.clone();
            let preview = still.path();
            still.install(root, &preview)?;
            return Ok(Prepared {
                digest,
                preview,
                motion: None,
                original_still: None,
                duration: None,
            });
        };
        let motion = Staged::resource(&dir, motion)?;
        let motion_path = motion.path();
        let digest = match &still {
            Some(still) => {
                let mut pair = Sha256::new();
                pair.update(still.digest.as_bytes());
                pair.update(motion.digest.as_bytes());
                format!("live-{:x}", pair.finalize())
            }
            None => format!("video-{}", motion.digest),
        };
        let poster = match self.poster {
            Some(p) => Staged::resource(&dir, p)?,
            None => match &still {
                Some(s) => Staged::copy(&dir, &mut s.file.reopen()?, s.ext)?,
                None => Staged::copy(
                    &dir,
                    &mut &include_bytes!("../../video-placeholder.png")[..],
                    "png",
                )?,
            },
        };
        let preview = format!("media/{digest}.{}", poster.ext);
        let original_still = still.as_ref().map(Staged::path);
        if let (Some(still), Some(path)) = (still, &original_still) {
            still.install(root, path)?;
        }
        motion.install(root, &motion_path)?;
        poster.install(root, &preview)?;
        Ok(Prepared {
            digest,
            preview,
            motion: Some(motion_path),
            original_still,
            duration: self.duration,
        })
    }
}

// The staging directory lives on the library volume. Its files are complete and
// synced before the database write lock is taken. Failed selections drop it whole.
struct Publication<'a> {
    root: &'a Path,
    stage: &'a Path,
    created: Vec<String>,
}

impl Publication<'_> {
    fn publish(&mut self, source: &str, destination: &str) -> Result<()> {
        Store::url(self.root, destination)?;
        let target = self.root.join(destination);
        if target.is_file() {
            return Ok(());
        }
        let parent = target.parent().ok_or("无效的媒体路径")?;
        fs::create_dir_all(parent)?;
        let staged = self.stage.join(source);
        if fs::hard_link(&staged, &target).is_err() {
            // Filesystems without hard links still publish an atomic, durable copy.
            let mut copy = NamedTempFile::new_in(parent)?;
            io::copy(&mut File::open(staged)?, copy.as_file_mut())?;
            copy.as_file().sync_all()?;
            copy.persist_noclobber(&target)?;
        }
        self.created.push(destination.to_owned());
        #[cfg(unix)]
        File::open(parent)?.sync_all()?;
        Ok(())
    }
    fn clean_rollback(self, db: &mut rusqlite::Connection) -> Result<()> {
        if self.created.is_empty() {
            return Ok(());
        }
        let cleanup = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        for path in self.created {
            let used: bool = cleanup.query_row(
                "SELECT EXISTS(SELECT 1 FROM photos WHERE path=?1)
                     OR EXISTS(SELECT 1 FROM media_resources WHERE motion=?1 OR original_still=?1)",
                [&path],
                |r| r.get(0),
            )?;
            if !used {
                fs::remove_file(self.root.join(path))?;
            }
        }
        cleanup.commit()?;
        Ok(())
    }
}

impl Store {
    pub fn import_media(&mut self, album: &str, files: Vec<MediaInput>) -> Result<ImportCounts> {
        self.db
            .query_row("SELECT 1 FROM albums WHERE id=?1", [album], |_| Ok(()))?;
        self.import_media_batch(album, None, files)
    }

    pub fn create_with_media(&mut self, name: &str, files: Vec<MediaInput>) -> Result<String> {
        if files.is_empty() {
            return Ok(String::new());
        }
        let id = Uuid::new_v4().to_string();
        self.import_media_batch(&id, Some(Self::name(name)?), files)?;
        Ok(id)
    }

    fn import_media_batch(
        &mut self,
        album: &str,
        name: Option<&str>,
        files: Vec<MediaInput>,
    ) -> Result<ImportCounts> {
        let mut counts = ImportCounts::default();
        let stage = tempfile::Builder::new()
            .prefix(".import-")
            .tempdir_in(self.root.join("media"))?;
        fs::create_dir(stage.path().join("media"))?;
        let mut prepared = Vec::new();
        for file in files {
            match file.validate() {
                Ok(asset) => prepared.push(asset.stage(stage.path())?),
                Err(e) if name.is_some() => return Err(format!("无法读取选中的媒体：{e}").into()),
                Err(_) => counts.skipped += 1,
            }
        }
        let mut publication = Publication {
            root: &self.root,
            stage: stage.path(),
            created: Vec::new(),
        };
        let write = || -> Result<()> {
            let tx = self
                .db
                .transaction_with_behavior(TransactionBehavior::Immediate)?;
            if let Some(name) = name {
                tx.execute("INSERT INTO albums(id,name) VALUES(?1,?2)", [album, name])?;
            } else {
                tx.query_row("SELECT 1 FROM albums WHERE id=?1", [album], |_| Ok(()))?;
            }
            for asset in prepared {
                let previous = tx
                    .query_row(
                        "SELECT p.id,p.path,m.motion,m.original_still FROM photos p
                 LEFT JOIN media_resources m ON m.photo=p.id WHERE p.digest=?1",
                        [&asset.digest],
                        |r| {
                            Ok((
                                r.get::<_, String>(0)?,
                                r.get::<_, String>(1)?,
                                r.get::<_, Option<String>>(2)?,
                                r.get::<_, Option<String>>(3)?,
                            ))
                        },
                    )
                    .optional()?;
                let (id, preview, motion, still) = match previous {
                    Some(row) => row,
                    None => {
                        let id = Uuid::new_v4().to_string();
                        tx.execute(
                            "INSERT INTO photos(id,path,digest) VALUES(?1,?2,?3)",
                            params![id, asset.preview, asset.digest],
                        )?;
                        if let Some(motion) = &asset.motion {
                            let kind = if asset.original_still.is_some() {
                                "live"
                            } else {
                                "video"
                            };
                            tx.execute("INSERT INTO media_resources(photo,kind,motion,original_still,duration) VALUES(?1,?2,?3,?4,?5)",params![id,kind,motion,asset.original_still,asset.duration])?;
                        }
                        (
                            id,
                            asset.preview.clone(),
                            asset.motion.clone(),
                            asset.original_still.clone(),
                        )
                    }
                };
                publication.publish(&asset.preview, &preview)?;
                if let (Some(source), Some(target)) = (&asset.motion, &motion) {
                    publication.publish(source, target)?;
                }
                if let (Some(source), Some(target)) = (&asset.original_still, &still) {
                    publication.publish(source, target)?;
                }
                let added = tx.execute("INSERT INTO members(album,photo,position) SELECT ?1,?2,COALESCE(MAX(position),-1)+1 FROM members WHERE album=?1 ON CONFLICT(album,photo) DO NOTHING",params![album,id])?;
                if added == 1 {
                    counts.added += 1
                } else {
                    counts.existing += 1
                }
            }
            tx.commit()?;
            Ok(())
        };
        if let Err(error) = write() {
            publication.clean_rollback(&mut self.db)?;
            return Err(error);
        }
        Ok(counts)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    const MOVIE: &[u8] =
        include_bytes!("../../../../toolchain/nsh/crates/nsh-platform-macos/tests/host/clip.mp4");
    const STILL: &[u8] = include_bytes!("../../tests/fixtures/first.png");

    #[test]
    fn mixed_batch_preserves_pairs_annotations_order_and_independent_stills() {
        let dir = tempfile::tempdir().unwrap();
        let input = tempfile::tempdir().unwrap();
        let still = input.path().join("IMG_0001.png");
        let movie = input.path().join("IMG_0001.mov");
        fs::write(&still, STILL).unwrap();
        fs::write(&movie, MOVIE).unwrap();
        let live = || MediaInput::Live {
            still: still.clone(),
            motion: movie.clone(),
            poster: None,
            duration: None,
        };
        let video = || MediaInput::Video {
            file: movie.clone(),
            poster: Some(still.clone()),
            duration: None,
        };
        let mut store = Store::open(dir.path().into()).unwrap();
        let id = store
            .create_with_media(
                "Mixed",
                vec![live(), video(), MediaInput::Photo(still.clone())],
            )
            .unwrap();
        let initial = store.library().unwrap();
        let ids = initial.albums[0].photo_ids.clone();
        store.cover(&id, &ids[1]).unwrap();
        store.annotate(&ids[0], "Live", "Note", "", "").unwrap();
        let dup = store.import_media(&id, vec![video(), live()]).unwrap();
        assert_eq!((dup.added, dup.existing, dup.skipped), (0, 2, 0));
        drop(input);
        drop(store);
        let mut store = Store::open(dir.path().into()).unwrap();
        let library = store.library().unwrap();
        assert_eq!(library.albums[0].photo_ids, ids);
        assert_eq!(library.albums[0].cover_id.as_ref(), Some(&ids[1]));
        let rows = &library.photos;
        assert_eq!(
            rows.iter().map(|p| p.kind.as_str()).collect::<Vec<_>>(),
            ["live", "video", "photo"]
        );
        assert_eq!(rows[0].description, "Note");
        assert_ne!(rows[0].url, rows[1].url);
        assert_ne!(rows[0].url, rows[2].url);
        for p in &rows[..2] {
            assert_eq!(fs::read(&p.url).unwrap(), STILL);
            assert_eq!(fs::read(p.video_url.as_ref().unwrap()).unwrap(), MOVIE);
            assert!(p.duration.unwrap() > 0.0);
        }
        let original: String = store
            .db
            .query_row(
                "SELECT original_still FROM media_resources WHERE kind='live'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(fs::read(dir.path().join(original)).unwrap(), STILL);
        assert_eq!(store.video_posters(&id).unwrap(), [rows[1].url.clone()]);
    }

    #[test]
    fn invalid_video_and_incomplete_live_pair_do_not_reach_membership() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path().into()).unwrap();
        let album = store.create("A").unwrap();
        let broken = dir.path().join("broken.mov");
        fs::write(&broken, b"\x00\x00\x00\x18ftypqt  ").unwrap();
        let counts = store
            .import_media(
                &album,
                vec![
                    MediaInput::Video {
                        file: broken.clone(),
                        poster: None,
                        duration: Some(1.0),
                    },
                    MediaInput::Live {
                        still: dir.path().join("missing"),
                        motion: broken,
                        poster: None,
                        duration: None,
                    },
                ],
            )
            .unwrap();
        assert_eq!((counts.added, counts.existing, counts.skipped), (0, 0, 2));
        assert!(store.playlist(&album).unwrap().is_empty());
    }

    #[test]
    fn upgrade_preserves_legacy_path_id_cover_note_and_membership() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("library.sqlite3");
        let db = Connection::open(&path).unwrap();
        db.execute_batch(include_str!("../../schema.sql")).unwrap();
        db.execute("INSERT INTO albums VALUES('album','Trip')", [])
            .unwrap();
        let hash = format!("{:x}", Sha256::digest(STILL));
        db.execute("INSERT INTO photos(id,path,digest,title) VALUES('local:old','media/import-old.png',?1,'Original note')",[hash]).unwrap();
        db.execute("INSERT INTO members VALUES('album','local:old',7)", [])
            .unwrap();
        db.execute("INSERT INTO covers VALUES('album','local:old')", [])
            .unwrap();
        drop(db);
        for _ in 0..2 {
            let mut store = Store::open(dir.path().into()).unwrap();
            assert_eq!(
                store
                    .db
                    .pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
                    .unwrap(),
                1
            );
            let copy = dir.path().join("new.png");
            fs::write(&copy, STILL).unwrap();
            assert_eq!(
                store
                    .import_media("album", vec![MediaInput::Photo(copy)])
                    .unwrap()
                    .existing,
                1
            );
            let library = store.library().unwrap();
            assert_eq!(library.albums[0].cover_id.as_deref(), Some("local:old"));
            let photo = &library.photos[0];
            assert_eq!(
                (&*photo.id, &*photo.kind, &*photo.title),
                ("local:old", "photo", "Original note")
            );
            assert!(photo.video_url.is_none() && photo.duration.is_none());
            assert!(
                photo.url.ends_with("media/import-old.png")
                    || photo.url.ends_with("media\\import-old.png")
            );
            assert_eq!(fs::read(&photo.url).unwrap(), STILL);
        }
    }

    #[test]
    fn failed_membership_removes_new_resources_and_preserves_shared_ones() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path().into()).unwrap();
        let movie = dir.path().join("input.mov");
        let still = dir.path().join("input.png");
        fs::write(&movie, MOVIE).unwrap();
        fs::write(&still, STILL).unwrap();
        let original = store
            .create_with_media("Original", vec![MediaInput::Photo(still.clone())])
            .unwrap();
        let shared = store.playlist(&original).unwrap().pop().unwrap();
        store
            .db
            .execute_batch(
                "CREATE TRIGGER fail_membership BEFORE INSERT ON members
             BEGIN SELECT RAISE(ABORT,'failed membership'); END;",
            )
            .unwrap();
        let failed = store.create_with_media(
            "Failed",
            vec![MediaInput::Live {
                still,
                motion: movie,
                poster: None,
                duration: None,
            }],
        );
        assert!(failed.is_err());
        assert_eq!(store.library().unwrap().albums.len(), 1);
        assert_eq!(fs::read(shared).unwrap(), STILL);
        assert_eq!(fs::read_dir(dir.path().join("media")).unwrap().count(), 1);
    }

    #[test]
    fn rollback_keeps_a_copy_claimed_by_another_writer() {
        let dir = tempfile::tempdir().unwrap();
        let mut first = Store::open(dir.path().into()).unwrap();
        let still = dir.path().join("input.png");
        fs::write(&still, STILL).unwrap();
        let stage = tempfile::tempdir_in(dir.path()).unwrap();
        fs::create_dir(stage.path().join("media")).unwrap();
        let asset = MediaInput::Photo(still.clone())
            .validate()
            .unwrap()
            .stage(stage.path())
            .unwrap();
        let mut publication = Publication {
            root: dir.path(),
            stage: stage.path(),
            created: vec![],
        };
        publication.publish(&asset.preview, &asset.preview).unwrap();
        // The failed transaction has released its lock. A separate connection
        // can commit a reference before the first connection reacquires it.
        let mut second = Store::open(dir.path().into()).unwrap();
        second
            .create_with_media("Other", vec![MediaInput::Photo(still)])
            .unwrap();
        publication.clean_rollback(&mut first.db).unwrap();
        let item = second.library().unwrap().photos.remove(0);
        assert_eq!(fs::read(item.url).unwrap(), STILL);
    }

    #[test]
    fn newer_schema_is_never_downgraded() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("library.sqlite3");
        let db = Connection::open(&path).unwrap();
        db.pragma_update(None, "user_version", 10).unwrap();
        drop(db);
        assert!(Store::open(dir.path().into()).is_err());
        assert_eq!(
            Connection::open(path)
                .unwrap()
                .pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
                .unwrap(),
            10
        );
    }
}
