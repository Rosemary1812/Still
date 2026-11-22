# Still native interface

`Photos` from `contactsheet/native`. Synchronous operations throw on failure. All mutation functions return void except `createAlbum`, which returns the album ID. Re-read `library()` after mutations. Picker calls are asynchronous.

```
library(): { albums: {id:string,name:string,photoIds:string[],coverId:string|null}[], photos: {id:string,kind:'photo'|'video'|'live',url:string,videoUrl:string|null,duration:number|null,title:string,description:string,date:string,location:string}[], viewMode:string }
createAlbum(name:string):string
createAlbumFromPicker(name:string):Promise<string> // empty on cancellation; album and picked photos committed together
renameAlbum(id:string,name:string):void
deleteAlbum(id:string):void
setCover(id:string,photoId:string):void
removePhoto(id:string,photoId:string):void
saveAnnotation(photoId:string,title:string,description:string,date:string,location:string):void
addFiles(id:string):Promise<Imported>
addApplePhotos(id:string):Promise<Imported>
addDropped(id:string,uris:string[]):Promise<Imported> // dropped file: URLs; folders are searched for supported media
// Imported = {added:number, existing:number, skipped:number}: new to the album, already in it, unreadable. Unreadable files never abort an import.
setViewMode(mode:string):void // cabinet or wall
playAlbum(id:string):void // start album; photos advance after 60 seconds and videos on playback completion
snapshot():{paths:string[],current:string|null,playing:boolean,revision:number,shuffle:boolean}
setShuffle(enabled:boolean):void // persisted, off by default
next():void; previous():void; toggle():void
finishVideo(poster:string,failed:boolean):void // complete the current video, ignoring stale callbacks
```

Library location: `$STILL_LIBRARY_DIR` override, otherwise `~/Library/Application Support/StillNSH` (macOS/iOS), `%LOCALAPPDATA%/StillNSH` (Windows), `$XDG_DATA_HOME/StillNSH` or `~/.local/share/StillNSH` (Linux). Database `library.sqlite3`; media paths are relative to that directory (normally `media/…`). `photos.path` is the still image or poster; `media_resources` links a video or Live Photo to its motion file, original Live still, and duration. See `schema.sql` and `media-schema.sql` for constraints. Schema version 1 preserves existing photo IDs, album membership, covers, and annotations. Albums use rowid order and members use position order. View setting key `viewMode`. UUID identifiers and content digests provide identity and deduplication. Only read safe relative paths.
