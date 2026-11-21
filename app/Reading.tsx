import { importSummary, mediaName, thisItem } from "./MediaLabels";
import { cleanup, effect, keymap, platform, reduceMotion, signal, Text, View, type ViewStyle } from "nsh";
import { AlertDialog, Button, Input } from "nsh/base";
import { currentWindow, Menu } from "nsh/desktop";
import { Photos } from "contactsheet/native";
import { type Anchor, fade, Icon, IconButton, onPhoto, onPhotoMuted, pill, Quiet, serif, stage } from "./AlbumControls";
import { Hint } from "./Controls";
import type { Library, Photo } from "./DesktopState";
import { PhotoWall } from "./PhotoWall";
import { Reader } from "./Reader";

type Source = "files" | "apple" | string[];
type Notice = { text: string; problem: boolean };
const cover: ViewStyle = { position: "absolute", top: 0, left: 0, right: 0, bottom: 0 };

export function Reading(p: { app: Library }) {
  const window = currentWindow();
  const width = signal(900), height = signal(600);
  const paused = signal(reduceMotion());
  effect(() => paused.set(reduceMotion()));
  const empty = () => p.app.photos().length === 0;
  const onWall = () => p.app.reading() === "wall";
  const name = () => p.app.album()?.name ?? "";

  // Messages stay inside the album: a line at the bottom, never a window over the photographs.
  const notice = signal<Notice | null>(null);
  let fading: ReturnType<typeof setTimeout> | undefined;
  function say(text: string, problem = false) {
    notice.set({ text, problem });
    clearTimeout(fading);
    fading = setTimeout(() => notice.set(null), problem ? 6000 : 3200);
  }
  const fail = (e: unknown) => say(String(e).replace(/^Error:\s*/, ""), true);

  // The wall is for looking: its controls leave while it drifts and return with the pointer.
  const awake = signal(true);
  let resting: ReturnType<typeof setTimeout> | undefined;
  function wake(rest = 2600) {
    if (!awake()) awake.set(true);
    clearTimeout(resting);
    resting = setTimeout(() => awake.set(false), rest);
  }
  wake();
  cleanup(() => { clearTimeout(resting); clearTimeout(fading); });

  const dropping = signal(false);
  async function add(source: Source) {
    if (p.app.busy()) return;
    const album = p.app.albumID();
    p.app.busy.set(true);
    try {
      const done = source === "files" ? await Photos.addFiles(album) : source === "apple" ? await Photos.addApplePhotos(album) : await Photos.addDropped(album, source);
      p.app.refresh();
      const text = importSummary(done);
      if (text) say(text, !!done.skipped && !done.added && !done.existing);
    } catch (e) { fail(e); } finally { p.app.busy.set(false); }
  }

  const renaming = signal(false);
  const draft = signal("");
  function rename() { draft.set(name()); renaming.set(true); }
  function endRename(save: boolean) {
    if (!renaming()) return;
    renaming.set(false);
    const next = draft().trim();
    if (!save || !next || next === name()) return;
    try { Photos.renameAlbum(p.app.albumID(), next); p.app.refresh(); } catch (e) { fail(e); }
  }

  function setCover(photo: Photo) {
    try { Photos.setCover(p.app.albumID(), photo.id); p.app.refresh(); say("已设为相册封面"); } catch (e) { fail(e); }
  }
  async function remove(photo: Photo) {
    const answer = await AlertDialog.show({ title: `从相册移除${thisItem(photo)}？`, description: `只从这本相册移除，原始${mediaName(photo)}不受影响。`, actions: [{ id: "cancel", label: "取消", role: "cancel" }, { id: "remove", label: "移除", role: "destructive" }] });
    if (answer.action !== "remove") return;
    const at = p.app.photos().findIndex(item => item.id === photo.id), current = p.app.photoID() === photo.id;
    try {
      Photos.removePhoto(p.app.albumID(), photo.id);
      p.app.refresh();
      if (!current) return;
      const next = p.app.photos()[Math.min(at, p.app.photos().length - 1)];
      if (next) p.app.photoID.set(next.id); else p.app.reading.set("wall");
    } catch (e) { fail(e); }
  }
  const isCover = (photo: Photo) => { const album = p.app.album(); return !!album && p.app.cover(album)?.id === photo.id; };
  function photoMenu(photo: Photo, at: { x: number; y: number }) {
    Menu.popup([
      onWall() && { label: `查看${mediaName(photo)}`, onSelect: () => p.app.select(photo.id) },
      { label: isCover(photo) ? "已是相册封面" : "设为相册封面", disabled: isCover(photo), onSelect: () => setCover(photo) },
      { type: "separator" },
      { label: "从相册移除…", onSelect: () => { remove(photo); } },
    ], at);
  }
  async function addMenu(anchor?: Anchor) {
    if (platform.os !== "macos") { add("files"); return; }
    Menu.popup([{ label: "从文件选择…", onSelect: () => { add("files"); } }, { label: "从 Apple 照片选择…", onSelect: () => { add("apple"); } }], await anchor?.());
  }
  function read() {
    const photo = p.app.photo() ?? p.app.photos()[0];
    if (photo) p.app.select(photo.id);
  }

  effect(() => {
    if (p.app.panel() !== "none") return;
    if (renaming()) { cleanup(keymap.bind({ escape: () => endRename(false) }, { when: "always" })); return; }
    cleanup(keymap.bind({
      escape: () => onWall() ? p.app.home() : p.app.reading.set("wall"),
      left: () => { if (!onWall()) p.app.step(-1); },
      right: () => { if (!onWall()) p.app.step(1); },
    }, { when: "notEditing" }));
  });

  const shown = () => awake() || !onWall() || empty() || paused() || renaming() || p.app.busy();
  const lights = () => platform.os === "macos" ? Math.max(window.titleBar().left, 72) : 0;
  return <View style={{ flex: 1, backgroundColor: stage }}
    onLayout={e => { width.set(e.bounds.size.width); height.set(e.bounds.size.height); }}
    onMouseMove={() => wake()} onMouseLeave={() => wake(700)}
    onFileDragEnter={() => dropping.set(true)} onFileDragLeave={() => dropping.set(false)}
    onFileDrop={e => { dropping.set(false); add(e.uris); }}>
    <If when={!empty()} else={
      <View testID="album-empty" style={{ flex: 1, alignItems: "center", justifyContent: "center", gap: 12 }}>
        <Button accessibilityLabel="添加照片" onPress={() => { addMenu(); }}
          style={{ width: 128, height: 128, borderRadius: 10, borderWidth: 1.5, borderStyle: "dashed", borderColor: "rgba(255,255,255,0.3)", alignItems: "center", justifyContent: "center", marginBottom: 10 }}
          hoverStyle={{ borderColor: "rgba(255,255,255,0.6)", backgroundColor: "rgba(255,255,255,0.04)" }} focusVisibleStyle={{ borderColor: "#9cc4fb" }}>
          <Icon name="plus" size={26} color="rgba(255,255,255,0.6)" />
        </Button>
        <Text style={{ color: onPhoto, fontSize: 24, fontFamily: serif }}>{name()}</Text>
        <Text style={{ color: onPhotoMuted, fontSize: 13 }}>这本相册还是空的。把照片、视频或文件夹拖进来，或者：</Text>
        <View style={{ flexDirection: "row", gap: 8, marginTop: 6 }}>
          <Quiet id="empty-files" label="从文件选择" filled disabled={p.app.busy()} onPress={() => { add("files"); }} />
          <If when={platform.os === "macos"}><Quiet id="empty-apple" label="从 Apple 照片选择" disabled={p.app.busy()} onPress={() => { add("apple"); }} /></If>
        </View>
      </View>}>
      <If when={onWall()} else={<Reader app={p.app} width={width()} fail={fail} cover={setCover} remove={photo => { remove(photo); }} menu={photoMenu} />}>
        <PhotoWall app={p.app} width={width()} height={height()} paused={paused() || renaming() || p.app.panel() !== "none"} menu={photoMenu} />
        <View style={{ ...cover, top: undefined, height: 170, justifyContent: "flex-end", paddingHorizontal: 26, paddingBottom: 22, gap: 4, pointerEvents: "none", backgroundImage: "linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.72) 100%)", opacity: shown() ? 1 : 0, ...fade, transitionDuration: 420 }}>
          <Text style={{ color: onPhoto, fontSize: 30, fontFamily: serif, numberOfLines: 1 }}>{name()}</Text>
          <Text style={{ color: onPhotoMuted, fontSize: 12.5, letterSpacing: 0.4 }}>{p.app.count(p.app.album())}</Text>
        </View>
      </If>
    </If>

    <View desktop={{ windowDrag: true }} style={{ ...cover, bottom: undefined, height: 46, flexDirection: "row", alignItems: "center", paddingLeft: lights() + 10, paddingRight: 10, gap: 10, opacity: shown() ? 1 : 0, ...fade }}>
      <View style={{ flex: 1, flexDirection: "row" }}>
        <View style={{ ...pill, padding: 3 }}><IconButton id="album-back" label="全部相册" icon="back" onPress={() => p.app.home()} /></View>
      </View>
      <If when={renaming()} else={<If when={!onWall() && !empty()}>
        <Button testID="album-title" accessibilityLabel={`${name()}，重命名`} tooltip={<Hint label="重命名" />} onPress={rename} style={{ ...pill, height: 36, paddingHorizontal: 16, justifyContent: "center", maxWidth: 320 }} hoverStyle={{ backgroundColor: "rgba(70,66,63,0.6)" }} focusVisibleStyle={{ borderColor: "#9cc4fb", borderWidth: 2 }}>
          <Text style={{ color: onPhoto, fontSize: 13.5, fontFamily: serif, numberOfLines: 1 }}>{name()}</Text>
        </Button>
      </If>}>
        <View style={{ ...pill, height: 36, paddingHorizontal: 6, justifyContent: "center" }}>
          <Input testID="album-rename" accessibilityLabel="相册名称" autoFocus value={draft()} onChange={e => draft.set(e.value)} onSubmit={() => endRename(true)} onBlur={() => endRename(true)}
            style={{ width: 240, height: 26, color: onPhoto, caretColor: onPhoto, fontSize: 13.5, fontFamily: serif, textAlign: "center", backgroundColor: "rgba(255,255,255,0.12)", borderRadius: 13, borderWidth: 0, paddingHorizontal: 10 }} />
        </View>
      </If>
      <View style={{ flex: 1, flexDirection: "row", justifyContent: "flex-end" }}>
        <View style={{ ...pill, flexDirection: "row", alignItems: "center", padding: 3, gap: 2 }}>
          <IconButton id="album-wall" label="照片墙" icon="wall" selected={onWall()} onPress={() => p.app.reading.set("wall")} />
          <IconButton id="album-read" label="翻阅" icon="reader" selected={!onWall()} disabled={empty()} onPress={() => read()} />
        </View>
      </View>
    </View>

    <If when={dropping()}>
      <View style={{ ...cover, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(18,17,16,0.62)", pointerEvents: "none" }}>
        <View style={{ paddingVertical: 22, paddingHorizontal: 34, borderRadius: 16, borderWidth: 1.5, borderStyle: "dashed", borderColor: "rgba(255,255,255,0.55)", alignItems: "center", gap: 6 }}>
          <Text style={{ color: onPhoto, fontSize: 17, fontFamily: serif }}>{`松开，添加到「${name()}」`}</Text>
          <Text style={{ color: onPhotoMuted, fontSize: 12.5 }}>支持照片、视频和文件夹</Text>
        </View>
      </View>
    </If>
    <If when={notice() || p.app.busy()}>
      <View style={{ ...cover, top: undefined, bottom: onWall() || empty() ? 24 : 86, alignItems: "center", pointerEvents: "box-none" }}>
        <View testID="album-notice" role="alert" style={{ ...pill, paddingVertical: 8, paddingHorizontal: 16, maxWidth: "80%" }}>
          <Text style={{ color: notice()?.problem && !p.app.busy() ? "#ffb1a8" : onPhoto, fontSize: 12.5 }}>{p.app.busy() ? "正在添加…" : notice()?.text ?? ""}</Text>
        </View>
      </View>
    </If>
  </View>;
}
