import { computed, signal } from "nsh";
import { Photos } from "contactsheet/native";

export type Album = ReturnType<typeof Photos.library>["albums"][number];
export type Photo = ReturnType<typeof Photos.library>["photos"][number];
export type GalleryMode = "wall" | "cabinet";
export type Panel = "none" | "inspect" | "settings" | "create" | "import" | "rename" | "manage" | "delete" | "remove" | "edit";

export function makeLibrary() {
  const library = signal<ReturnType<typeof Photos.library>>({ albums: [], photos: [], viewMode: "cabinet" });
  const player = signal(Photos.snapshot());
  const albumID = signal("");
  const photoID = signal("");
  const reading = signal<"home" | "wall" | "book" | "preview">("home");
  const panel = signal<Panel>("none");
  const error = signal("");
  command(refresh);
  const busy = signal(false);
  const album = computed(() => library().albums.find(a => a.id === albumID()));
  const photoMap = computed(() => new Map(library().photos.map(p => [p.id, p])));
  const photos = computed(() => (album()?.photoIds ?? []).flatMap(id => { const p = photoMap().get(id); return p ? [p] : []; }));
  const index = computed(() => photos().findIndex(p => p.id === photoID()));
  const photo = computed(() => photoMap().get(photoID()));
  function refresh() { library.set(Photos.library()); }
  function command(fn: () => void) { try { error.set(""); fn(); } catch(e) { error.set(String(e)); } }
  function mutate(fn: () => void, done: () => void = () => panel.set("none")) { command(() => { fn(); refresh(); done(); }); }
  function changeView(mode: GalleryMode) { mutate(() => Photos.setViewMode(mode), () => {}); }
  function inspect(id: string) { albumID.set(id); panel.set("inspect"); }
  function openAlbum(id: string) { albumID.set(id); photoID.set(""); panel.set("none"); reading.set("wall"); }
  function home() { reading.set("home"); panel.set("none"); albumID.set(""); photoID.set(""); }
  function select(id: string, mode: "book" | "preview") { photoID.set(id); reading.set(mode); }
  function step(delta: number) { const target = photos()[index() + delta]; if (target) photoID.set(target.id); }
  function remove() { const pos = index(); mutate(() => Photos.removePhoto(albumID(), photoID()), () => { panel.set("none"); const p = photos()[Math.min(pos, photos().length - 1)]; if (p) photoID.set(p.id); else reading.set("wall"); }); }
  async function addPhotos(source: "files" | "apple") {
    if (busy()) return;
    busy.set(true); error.set("");
    try { if (source === "files") await Photos.addFiles(albumID()); else await Photos.addApplePhotos(albumID()); refresh(); panel.set("none"); }
    catch(e) { error.set(String(e)); } finally { busy.set(false); }
  }
  function control(fn: () => void) { command(() => { fn(); player.set(Photos.snapshot()); }); }
  function cover(a: Album) { return photoMap().get(a.coverId ?? a.photoIds[0] ?? ""); }
  return { library, player, albumID, photoID, reading, panel, error, busy, album, photos, photo, index, cover, refresh, command, mutate, changeView, inspect, openAlbum, home, select, step, remove, addPhotos, control };
}
export type Library = ReturnType<typeof makeLibrary>;
