# Still native interface

`Photos` from `contactsheet/native`. Synchronous operations throw on failure. All mutation functions return void except `createAlbum`, which returns the album ID. Re-read `library()` after mutations. Picker calls are asynchronous.

```
library(): { albums: {id:string,name:string,photoIds:string[],coverId:string|null}[], photos: {id:string,url:string,title:string,description:string,date:string,location:string}[], viewMode:string }
createAlbum(name:string):string
createAlbumFromPicker(name:string):Promise<string> // empty on cancellation; album and picked photos committed together
renameAlbum(id:string,name:string):void
deleteAlbum(id:string):void
setCover(id:string,photoId:string):void
removePhoto(id:string,photoId:string):void
saveAnnotation(photoId:string,title:string,description:string,date:string,location:string):void
addFiles(id:string):Promise<void>
addApplePhotos(id:string):Promise<void>
setViewMode(mode:string):void // cabinet or wall
playAlbum(id:string):void // start album, 60 seconds between photos
snapshot():{paths:string[],current:string|null,playing:boolean,revision:number,shuffle:boolean}
setShuffle(enabled:boolean):void // persisted, off by default
next():void; previous():void; toggle():void
```

Library location: `$STILL_LIBRARY_DIR` override, otherwise `~/Library/Application Support/StillNSH` (macOS/iOS), `%LOCALAPPDATA%/StillNSH` (Windows), `$XDG_DATA_HOME/StillNSH` or `~/.local/share/StillNSH` (Linux). Database `library.sqlite3`; media paths are relative to that directory (normally `media/…`). Schema: `albums(id TEXT PRIMARY KEY,name TEXT NOT NULL)`, `photos(id TEXT PRIMARY KEY,path TEXT NOT NULL UNIQUE,digest TEXT UNIQUE,title TEXT NOT NULL DEFAULT '',description TEXT NOT NULL DEFAULT '',date TEXT NOT NULL DEFAULT '',location TEXT NOT NULL DEFAULT '')`, `members(album TEXT,photo TEXT,position INTEGER,PRIMARY KEY(album,photo))`, `covers(album TEXT PRIMARY KEY,photo TEXT)`, `settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)`; rowid ordering for albums, position ordering for members. See schema.sql for constraints. View setting key `viewMode`. UUID identifiers except content digests for deduplication; use legacy IDs as-is during migration. Only read safe relative paths.
