// Each import owns one locked journal until its SQLite commit or rollback finishes.
// A process death releases the OS lock. Startup then reclaims its staging directory
// and checks the surviving database before removing any links it published.
use super::{Result, Store};
use rusqlite::{Connection, Transaction, TransactionBehavior};
use std::{
    fs::{self, File, OpenOptions, TryLockError},
    io::{self, BufRead, BufReader, Write},
    path::Path,
};
use tempfile::TempDir;

pub(super) struct Stage {
    // Close the file before TempDir removes its directory on Windows.
    pub journal: File,
    dir: TempDir,
}

impl Stage {
    pub fn create(root: &Path, db: &mut Connection) -> Result<Self> {
        // A concurrent opener cannot observe the interval between mkdir and lock.
        let setup = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let parent = root.join(".imports");
        fs::create_dir_all(&parent)?;
        let dir = tempfile::Builder::new()
            .prefix("batch-")
            .tempdir_in(&parent)?;
        let journal = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(dir.path().join("journal"))?;
        journal.lock()?;
        fs::create_dir(dir.path().join("media"))?;
        #[cfg(unix)]
        {
            File::open(dir.path())?.sync_all()?;
            File::open(&parent)?.sync_all()?;
            File::open(root)?.sync_all()?;
        }
        setup.commit()?;
        Ok(Self { journal, dir })
    }
    pub fn path(&self) -> &Path {
        self.dir.path()
    }
}

pub(super) fn record(journal: &mut File, relative: &str) -> Result<()> {
    serde_json::to_writer(&mut *journal, relative)?;
    journal.write_all(b"\n")?;
    journal.sync_all()?;
    Ok(())
}

pub(super) fn remove_unused(db: &Transaction<'_>, root: &Path, relative: &str) -> Result<()> {
    // Journals can only own managed media. A malformed journal must never
    // remove the SQLite database or another file under the library root.
    if !Path::new(relative).starts_with("media") || Store::url(root, relative).is_err() {
        return Ok(());
    }
    let used: bool = db.query_row(
        "SELECT EXISTS(SELECT 1 FROM photos WHERE path=?1)
             OR EXISTS(SELECT 1 FROM media_resources WHERE motion=?1 OR original_still=?1)",
        [relative],
        |r| r.get(0),
    )?;
    if !used {
        match fs::remove_file(root.join(relative)) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

/// Called while holding SQLite's immediate transaction, which excludes stage
/// creation and publication by other workers. Workers hashing files keep a lease.
pub(super) fn recover(root: &Path, db: &Transaction<'_>) -> Result<()> {
    let entries = match fs::read_dir(root.join(".imports")) {
        Ok(entries) => entries,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e.into()),
    };
    for entry in entries {
        let entry = entry?;
        let file_type = match entry.file_type() {
            Ok(kind) => kind,
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e.into()),
        };
        if !file_type.is_dir() || !entry.file_name().to_string_lossy().starts_with("batch-") {
            continue;
        }
        let path = entry.path();
        match OpenOptions::new()
            .read(true)
            .write(true)
            .open(path.join("journal"))
        {
            Ok(journal) => {
                match journal.try_lock() {
                    Ok(()) => {}
                    Err(TryLockError::WouldBlock) => continue,
                    Err(TryLockError::Error(e)) => return Err(e.into()),
                }
                let mut reader = BufReader::new(journal);
                let mut line = Vec::new();
                loop {
                    line.clear();
                    if reader.read_until(b'\n', &mut line)? == 0 {
                        break;
                    }
                    // Publication only starts after a complete line is synced.
                    if line.last() != Some(&b'\n') {
                        break;
                    }
                    if let Ok(relative) = serde_json::from_slice::<String>(&line) {
                        remove_unused(db, root, &relative)?;
                    }
                }
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
        }
        match fs::remove_dir_all(path) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        process::{Child, Command},
        thread,
        time::{Duration, Instant},
    };

    #[test]
    fn interrupted_import_worker() {
        let Some(root) = std::env::var_os("STILL_CRASH_TEST_LIBRARY") else {
            return;
        };
        let root = Path::new(&root);
        let mut store = Store::open(root.into()).unwrap();
        let mut stage = Stage::create(root, &mut store.db).unwrap();
        fs::write(stage.path().join("media/video.mp4"), b"partial staging").unwrap();
        fs::write(root.join("ready"), b"").unwrap();
        while !root.join("publish").exists() {
            thread::sleep(Duration::from_millis(10));
        }
        let _writer = store
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .unwrap();
        record(&mut stage.journal, "media/crashed.mp4").unwrap();
        fs::hard_link(
            stage.path().join("media/video.mp4"),
            root.join("media/crashed.mp4"),
        )
        .unwrap();
        fs::write(root.join("published"), b"").unwrap();
        loop {
            thread::sleep(Duration::from_secs(1));
        }
    }

    #[test]
    fn abandoned_journal_preserves_committed_files_and_ignores_partial_records() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let mut store = Store::open(root.into()).unwrap();
        let still = root.join("input.png");
        fs::write(&still, include_bytes!("../../tests/fixtures/first.png")).unwrap();
        store
            .create_with_media("Saved", vec![super::super::MediaInput::Photo(still)])
            .unwrap();
        let relative: String = store
            .db
            .query_row("SELECT path FROM photos", [], |r| r.get(0))
            .unwrap();
        let abandoned = root.join(".imports/batch-test");
        fs::create_dir(&abandoned).unwrap();
        let mut journal = File::create(abandoned.join("journal")).unwrap();
        for item in [&*relative, "library.sqlite3", "media/../library.sqlite3"] {
            record(&mut journal, item).unwrap();
        }
        journal.write_all(b"partial line without newline").unwrap();
        drop(journal);
        drop(store);
        let mut reopened = Store::open(root.into()).unwrap();
        assert_eq!(reopened.library().unwrap().photos.len(), 1);
        assert!(root.join(relative).is_file());
        assert!(!abandoned.exists());
    }
    struct Worker(Child);
    impl Drop for Worker {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    fn await_file(path: &Path, worker: &mut Child) {
        let deadline = Instant::now() + Duration::from_secs(15);
        while !path.exists() {
            assert!(
                worker.try_wait().unwrap().is_none(),
                "worker exited before {}",
                path.display()
            );
            assert!(
                Instant::now() < deadline,
                "worker timed out waiting for {}",
                path.display()
            );
            thread::sleep(Duration::from_millis(10));
        }
    }

    #[test]
    fn reopening_preserves_a_live_worker_and_reclaims_its_uncommitted_files_after_kill() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let mut child = Worker(
            Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "store::recovery::tests::interrupted_import_worker",
                ])
                .env("STILL_CRASH_TEST_LIBRARY", root)
                .spawn()
                .unwrap(),
        );
        await_file(&root.join("ready"), &mut child.0);
        drop(Store::open(root.into()).unwrap());
        assert_eq!(fs::read_dir(root.join(".imports")).unwrap().count(), 1);
        fs::write(root.join("publish"), b"").unwrap();
        await_file(&root.join("published"), &mut child.0);
        child.0.kill().unwrap();
        child.0.wait().unwrap();
        assert!(root.join("media/crashed.mp4").is_file());
        let mut opened = Store::open(root.into()).unwrap();
        assert!(opened.library().unwrap().albums.is_empty());
        assert_eq!(fs::read_dir(root.join(".imports")).unwrap().count(), 0);
        assert_eq!(fs::read_dir(root.join("media")).unwrap().count(), 0);
    }
}
