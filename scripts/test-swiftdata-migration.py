#!/usr/bin/env python3
"""Exercise old-library imports without depending on a user's Photos library or Mac."""
import base64
import hashlib
from pathlib import Path
import runpy
import sqlite3
import tempfile
import unittest
import uuid

migrate = runpy.run_path(str(Path(__file__).with_name('migrate-swiftdata.py')))['migrate']


class Migration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        self.old = home / 'legacy/library.store'
        self.imports = self.old.parent / 'Imports'
        self.imports.mkdir(parents=True)
        self.dest = home / 'new'
        self.db = sqlite3.connect(self.old)
        self.addCleanup(self.db.close)
        self.db.executescript('''
          PRAGMA journal_mode=WAL;
          CREATE TABLE Z_METADATA(Z_UUID TEXT);
          INSERT INTO Z_METADATA VALUES('fixture-1');
          CREATE TABLE ZCONTACTALBUM(Z_PK INTEGER PRIMARY KEY,ZID BLOB,ZNAME,ZCOVERASSETID,ZCREATEDAT,ZUPDATEDAT);
          CREATE TABLE ZALBUMPHOTO(Z_PK INTEGER PRIMARY KEY,ZID BLOB,Z2PHOTOS INTEGER,ZASSETIDENTIFIER,ZSORTINDEX INTEGER);
          CREATE TABLE ZPHOTOANNOTATION(ZASSETIDENTIFIER,ZTITLE,ZDESCRIPTIONTEXT,ZLOCATIONTEXT,ZDISPLAYDATE,ZUPDATEDAT);
        ''')
        self.image = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAC0lEQVR4nGNgAAIAAAUAAen63NgAAAAASUVORK5CYII=')
        self.local = 'local:' + hashlib.sha256(self.image).hexdigest() + '.image'
        self.image_file = self.imports / self.local[6:]
        self.image_file.write_bytes(self.image)
        self.apple = 'photo:distinct-but-identical/L0/1'
        for i, name in [(1, 'old'), (2, 'new')]:
            self.db.execute('insert into ZCONTACTALBUM values(?,?,?,?,?,?)', (i, uuid.UUID(int=i).bytes, name, self.local, i, i))
            self.db.execute('insert into ZALBUMPHOTO(ZID,Z2PHOTOS,ZASSETIDENTIFIER,ZSORTINDEX) values(?,?,?,?)',(uuid.uuid4().bytes, i, self.local, 1))
        self.db.execute('insert into ZALBUMPHOTO(ZID,Z2PHOTOS,ZASSETIDENTIFIER,ZSORTINDEX) values(?,?,?,?)',(uuid.uuid4().bytes, 2, self.apple, 0))
        self.db.execute('insert into ZPHOTOANNOTATION values(?,?,?,?,?,?)',(self.apple, 'A', 'B', 'C', 123456789, 9))
        self.db.commit()

    def run_import(self):
        return migrate(self.old, self.imports, self.dest, apple_files={self.apple: str(self.image_file)})

    def test_roundtrip_and_reimport(self):
        self.run_import()
        with sqlite3.connect(self.dest / 'library.sqlite3') as conn:
            self.assertEqual(conn.execute('select name from albums order by rowid').fetchall(), [('new',), ('old',)])
            album = str(uuid.UUID(int=2)).upper()
            self.assertEqual(conn.execute('select photo from members where album=? order by position',(album,)).fetchall(), [(self.apple,),(self.local,)])
            self.assertEqual(conn.execute('select photo from covers where album=?',(album,)).fetchone(),(self.local,))
            self.assertEqual(conn.execute('select title,description,location from photos where id=?',(self.apple,)).fetchone(), ('A','B','C'))
            self.assertTrue(conn.execute('select date from photos where id=?',(self.apple,)).fetchone()[0])
            for path, in conn.execute('select path from photos'):
                self.assertEqual((self.dest/path).read_bytes(), self.image)
            conn.execute("update albums set name='edited' where id=?", (album,))
        self.assertIn('Already imported', self.run_import())
        with sqlite3.connect(self.dest/'library.sqlite3') as conn:
            self.assertEqual(conn.execute('select name from albums where id=?',(album,)).fetchone(), ('edited',))
        self.db.execute("update ZCONTACTALBUM set ZNAME='source changed' where Z_PK=2")
        self.db.commit()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.run_import()

    def test_missing_apple_file_and_corruption_are_atomic(self):
        with self.assertRaisesRegex(ValueError,'Apple Photos originals required'):
            migrate(self.old,self.imports,self.dest)
        self.assertFalse(self.dest.exists())
        self.image_file.write_bytes(self.image + b'mismatch')
        with self.assertRaisesRegex(ValueError,'hash mismatch'):
            self.run_import()
        self.assertFalse(self.dest.exists())

    def test_preserves_existing_directories(self):
        self.dest.mkdir()
        marker = self.dest / 'keep'
        marker.write_text('existing')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.run_import()
        self.assertEqual(marker.read_text(),'existing')
        with self.assertRaisesRegex(ValueError, 'outside'):
            migrate(self.old,self.imports,self.imports/'new')


if __name__ == '__main__':
    unittest.main()
