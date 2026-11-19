#!/usr/bin/env python3
"""Import one Still SwiftData snapshot into a new NSH library, without changing the source."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
from contextlib import closing
import plistlib
import re
import sqlite3
import sys
import tempfile
import uuid


SUPPORT = Path.home() / 'Library/Containers/local.contact-sheet.app/Data/Library/Application Support'
EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
ROOT = Path(__file__).resolve().parents[1]


def connect_ro(path):
    return sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)


def snapshot(path):
    # SQLite's backup API sees committed WAL transactions, including those newer than the main file.
    snap = sqlite3.connect(':memory:')
    with closing(connect_ro(path)) as source:
        source.backup(snap)
    snap.row_factory = sqlite3.Row
    if snap.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
        raise ValueError('Legacy SQLite integrity check failed')
    return snap


def fingerprint(path):
    digest = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def copy_media(source, media, expected=None):
    if source.is_symlink() or not source.is_file():
        raise ValueError(f'Missing or non-regular image: {source}')
    digest = hashlib.sha256()
    with source.open('rb') as src, tempfile.NamedTemporaryFile(dir=media, delete=False) as out:
        header = src.read(32)
        chunk = header
        while chunk:
            digest.update(chunk)
            out.write(chunk)
            chunk = src.read(1024 * 1024)
    value = digest.hexdigest()
    if expected and value != expected:
        raise ValueError(f'Legacy file hash mismatch: {source.name}')
    if header.startswith(b'\xff\xd8\xff'):
        ext = 'jpg'
    elif header.startswith(b'\x89PNG\r\n\x1a\n'):
        ext = 'png'
    elif header.startswith((b'GIF87a', b'GIF89a')):
        ext = 'gif'
    elif header.startswith(b'RIFF') and header[8:12] == b'WEBP':
        ext = 'webp'
    elif header[4:8] == b'ftyp' and header[8:12] in (b'heic', b'heix', b'hevc', b'mif1', b'msf1'):
        ext = 'heic'
    else:
        raise ValueError(f'Unrecognized image format: {source.name}')
    target = media / (value + '.' + ext)
    if target.exists():
        os.unlink(out.name)
    else:
        os.replace(out.name, target)
    if fingerprint(target) != value:
        raise ValueError('Copied media failed SHA-256 verification')
    return 'media/' + target.name, value


def source_data(db):
    albums = [dict(row) for row in db.execute('SELECT Z_PK AS pk,ZID AS id,ZNAME AS name,ZCOVERASSETID AS cover,ZCREATEDAT AS created,ZUPDATEDAT AS updated FROM ZCONTACTALBUM ORDER BY ZCREATEDAT DESC,Z_PK')]
    by_pk = {}
    for album in albums:
        by_pk[album.pop('pk')] = album
        album['id'] = str(uuid.UUID(bytes=album['id'])).upper()
        album['members'] = []
    photos = set()
    for row in db.execute('SELECT Z2PHOTOS,ZASSETIDENTIFIER,ZSORTINDEX,ZID FROM ZALBUMPHOTO ORDER BY Z2PHOTOS,ZSORTINDEX,Z_PK'):
        album = by_pk.get(row[0])
        if album is None:
            raise ValueError('Orphan SwiftData album membership')
        album['members'].append({'photo': row[1], 'position': row[2], 'id': str(uuid.UUID(bytes=row[3])).upper()})
        photos.add(row[1])
    for a in albums:
        if a['cover'] and a['cover'] not in {m['photo'] for m in a['members']}:
            raise ValueError('Legacy cover is not a member of its album')
    annotations = {r['id']: dict(r) for r in db.execute('SELECT ZASSETIDENTIFIER AS id,ZTITLE AS title,ZDESCRIPTIONTEXT AS description,ZLOCATIONTEXT AS location,ZDISPLAYDATE AS date,ZUPDATEDAT AS updated FROM ZPHOTOANNOTATION')}
    identifier, = db.execute('SELECT Z_UUID FROM Z_METADATA').fetchone()
    return {'source': identifier, 'albums': albums, 'annotations': annotations}, sorted(photos | set(annotations))


def view_mode(prefs):
    if not prefs or not prefs.exists():
        return 'cabinet'
    with prefs.open('rb') as f:
        v = plistlib.load(f).get('albumGalleryView', 'cabinet')
    return {'grid': 'wall', 'cabinet': 'cabinet', 'wall': 'wall'}[v]


def migrate(source, imports, destination, prefs=None, apple_files=None):
    source, imports = source.resolve(), imports.resolve()
    destination = destination.expanduser().absolute()
    target = destination.resolve()
    if (destination.is_symlink() or target == source or target in source.parents or
            target == imports or target in imports.parents or imports in target.parents):
        raise ValueError('Choose a new destination outside the legacy library')
    with closing(snapshot(source)) as legacy:
        data, ids = source_data(legacy)
    data['viewMode'] = view_mode(prefs)
    signature = hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    receipt = destination / 'legacy-import.json'
    if destination.exists():
        if receipt.is_file() and (destination / 'library.sqlite3').is_file():
            previous = json.loads(receipt.read_text())
            if previous.get('snapshotSHA256') == signature:
                return 'Already imported: existing NSH edits and files were left unchanged.'
        raise ValueError('Destination already exists; choose a fresh directory. No existing library was changed.')
    needs_exports = [key for key in ids if key.startswith('photo:') and key not in (apple_files or {})]
    if needs_exports:
        raise ValueError('Apple Photos originals required. Supply --apple-files JSON with these exact asset identifiers: ' + ', '.join(needs_exports))
    schema = ROOT / 'app/native/schema.sql'
    if not schema.is_file():
        raise ValueError('Missing Still native schema.sql')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.still-migration-', dir=destination.parent) as temporary:
        stage = Path(temporary) / 'library'
        media = stage / 'media'
        media.mkdir(parents=True)
        with sqlite3.connect(stage / 'library.sqlite3') as new:
            new.execute('PRAGMA foreign_keys=ON')
            new.executescript(schema.read_text())
            digests = set()
            for key in ids:
                match = re.fullmatch(r'local:([0-9a-f]{64})\.image', key)
                if match:
                    path, digest = copy_media(imports / (match[1] + '.image'), media, match[1])
                elif key.startswith('photo:'):
                    path, digest = copy_media(Path(apple_files[key]), media)
                else:
                    raise ValueError('Unrecognized legacy identifier: ' + key)
                if digest in digests:
                    # Distinct Photos identifiers may contain identical bytes but carry different notes.
                    alias = Path(path).with_name(digest + '-' + hashlib.sha256(key.encode()).hexdigest() + Path(path).suffix)
                    os.link(stage / path, stage / alias)
                    path, digest = alias.as_posix(), None
                else:
                    digests.add(digest)
                annotation = data['annotations'].get(key, {})
                date = annotation.get('date')
                date_text = '' if date is None else (EPOCH + dt.timedelta(seconds=date)).astimezone().date().isoformat()
                new.execute('INSERT INTO photos(id,path,digest,title,description,date,location) VALUES(?,?,?,?,?,?,?)', (key, path, digest, annotation.get('title', ''), annotation.get('description', ''), date_text, annotation.get('location', '')))
            members = 0
            for album in data['albums']:
                aid = album['id']
                new.execute('INSERT INTO albums(id,name) VALUES(?,?)', (aid, album['name']))
                for m in album['members']:
                    new.execute('INSERT INTO members(album,photo,position) VALUES(?,?,?)', (aid, m['photo'], m['position']))
                    members += 1
                if album['cover']:
                    new.execute('INSERT INTO covers(album,photo) VALUES(?,?)', (aid, album['cover']))
            new.execute("INSERT OR REPLACE INTO settings(key,value) VALUES('viewMode',?)", (data['viewMode'],))
            if new.execute('PRAGMA foreign_key_check').fetchone() or new.execute('PRAGMA integrity_check').fetchone() != ('ok',):
                raise ValueError('Migrated database failed integrity checks')
        new.close()
        (stage / receipt.name).write_text(json.dumps({'version': 1, 'snapshotSHA256': signature, **data}, ensure_ascii=False))
        # A concurrently created nonempty directory cannot be overwritten by rename(2).
        if destination.exists():
            raise ValueError('Destination appeared during migration; no changes installed')
        stage.rename(destination)
    return f"Imported {len(data['albums'])} albums, {members} memberships, {len(ids)} unique assets and {len(data['annotations'])} annotations."


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=SUPPORT / 'default.store')
    parser.add_argument('--imports', type=Path, help='Defaults to ContactSheet/Imports beside the source store')
    parser.add_argument('--preferences', type=Path, help='Old preferences plist (automatically located for sandbox sources)')
    parser.add_argument('--destination', type=Path, required=True, help='New directory; an existing library is never overwritten')
    parser.add_argument('--apple-files', type=Path, help='JSON object mapping photo: identifiers to exported original image paths')
    args = parser.parse_args()
    try:
        assets = json.loads(args.apple_files.read_text()) if args.apple_files else {}
        prefs = args.preferences
        if not prefs and args.source.parent.name == 'Application Support' and args.source.parent.parent.parent.name == 'Data':
            prefs = args.source.parents[1] / 'Preferences' / (args.source.parents[3].name + '.plist')
        print(migrate(args.source, args.imports or args.source.parent / 'ContactSheet/Imports', args.destination, prefs, assets))
    except (sqlite3.Error, OSError, ValueError, KeyError) as exc:
        sys.exit('Migration stopped: ' + str(exc))
