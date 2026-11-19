// The previous iOS app kept its SwiftData store and managed imports in this sandbox.
use crate::store::Result;
use rusqlite::{Connection, OpenFlags, OptionalExtension, params};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
};
use uuid::Uuid;

fn install_media(imports: &Path, root: &Path, id: &str) -> Result<(String, String)> {
    let filename = id
        .strip_prefix("local:")
        .ok_or("未知的旧版 iPhone 照片标识")?;
    let digest = filename.strip_suffix(".image").ok_or("无效的旧版照片名")?;
    if digest.len() != 64 || !digest.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("旧版照片的摘要无效".into());
    }
    let bytes = fs::read(imports.join(filename))?;
    if format!("{:x}", Sha256::digest(&bytes)) != digest {
        return Err("旧版照片完整性检查失败".into());
    }
    let ext = if bytes.starts_with(b"\xff\xd8\xff") {
        "jpg"
    } else if bytes.starts_with(b"\x89PNG") {
        "png"
    } else if bytes.get(4..8) == Some(b"ftyp") {
        "heic"
    } else {
        "image"
    };
    let relative = format!("media/{digest}.{ext}");
    let dest = root.join(&relative);
    if dest.exists() {
        if format!("{:x}", Sha256::digest(fs::read(&dest)?)) != digest {
            return Err("目标照片完整性检查失败".into());
        }
    } else {
        let mut tmp = tempfile::NamedTempFile::new_in(root.join("media"))?;
        tmp.write_all(&bytes)?;
        tmp.as_file().sync_all()?;
        tmp.persist_noclobber(dest)?;
    }
    Ok((relative, digest.to_owned()))
}

pub fn import(db: &mut Connection, root: &Path) -> Result<()> {
    let old = PathBuf::from(root.parent().ok_or(io::Error::other("缺少图库目录"))?).join("Still");
    let file = old.join("library.store");
    if !file.is_file()
        || db
            .query_row(
                "SELECT 1 FROM settings WHERE key='iosSwiftDataImported'",
                [],
                |_| Ok(()),
            )
            .optional()?
            .is_some()
    {
        return Ok(());
    }
    let mut source = Connection::open_with_flags(file, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let read = source.transaction()?;
    let tx = db.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let mut albums = read.prepare(
        "SELECT Z_PK,ZID,ZNAME,ZCOVERASSETID FROM ZCONTACTALBUM ORDER BY ZCREATEDAT DESC,Z_PK",
    )?;
    let mut rows = albums.query([])?;
    while let Some(row) = rows.next()? {
        let pk: i64 = row.get(0)?;
        let id = Uuid::from_slice(&row.get::<_, Vec<u8>>(1)?)?.to_string();
        let name: String = row.get(2)?;
        let cover: Option<String> = row.get(3)?;
        tx.execute(
            "INSERT INTO albums(id,name) VALUES(?1,?2)",
            params![id, name],
        )?;
        let mut members = read.prepare("SELECT ZASSETIDENTIFIER,ZSORTINDEX FROM ZALBUMPHOTO WHERE Z2PHOTOS=?1 ORDER BY ZSORTINDEX,Z_PK")?;
        let mut entries = members.query([pk])?;
        while let Some(entry) = entries.next()? {
            let asset: String = entry.get(0)?;
            let order: i64 = entry.get(1)?;
            if tx
                .query_row("SELECT 1 FROM photos WHERE id=?1", [&asset], |_| Ok(()))
                .optional()?
                .is_none()
            {
                let (path, digest) = install_media(&old.join("Imports"), root, &asset)?;
                tx.execute(
                    "INSERT INTO photos(id,path,digest) VALUES(?1,?2,?3)",
                    params![asset, path, digest],
                )?;
            }
            tx.execute(
                "INSERT INTO members(album,photo,position) VALUES(?1,?2,?3)",
                params![id, asset, order],
            )?;
        }
        if let Some(cover) = cover {
            tx.execute(
                "INSERT INTO covers(album,photo) VALUES(?1,?2)",
                params![id, cover],
            )?;
        }
    }
    let mut notes = read.prepare("SELECT ZASSETIDENTIFIER,ZTITLE,ZDESCRIPTIONTEXT,ZLOCATIONTEXT,coalesce(strftime('%Y-%m-%d',ZDISPLAYDATE+978307200,'unixepoch'),'') FROM ZPHOTOANNOTATION")?;
    let mut rows = notes.query([])?;
    while let Some(row) = rows.next()? {
        let field = |i: usize| row.get::<_, String>(i);
        tx.execute(
            "UPDATE photos SET title=?2,description=?3,location=?4,date=?5 WHERE id=?1",
            params![field(0)?, field(1)?, field(2)?, field(3)?, field(4)?],
        )?;
    }
    tx.execute(
        "INSERT INTO settings(key,value) VALUES('iosSwiftDataImported','1')",
        [],
    )?;
    tx.commit()?;
    Ok(())
}
