import { itemLabel, mediaName, thisItem } from "./MediaLabels";
import { currentWindow } from "nsh/desktop";
import { MotionMedia } from "./MotionMedia";
import { cleanup, computed, effect, Image, keymap, Scroll, signal, Text, untracked, View, type InputRef, type InputStyle, type ScrollRef, type Signal } from "nsh";
import { Button, Input } from "nsh/base";
import { Photos } from "contactsheet/native";
import { fade, Icon, onPhoto, onPhotoFaint, onPhotoMuted, pill, Quiet, serif, stage } from "./AlbumControls";
import { Artwork } from "./Gallery";
import type { Library, Photo } from "./DesktopState";

const field: InputStyle = {
  color: onPhoto, placeholderColor: onPhotoFaint, caretColor: onPhoto,
  backgroundColor: "transparent", borderWidth: 0, borderRadius: 7, paddingHorizontal: 8, marginHorizontal: -8,
};
const fieldHover = { backgroundColor: "rgba(255,255,255,0.06)" };
const fieldFocus = { backgroundColor: "rgba(255,255,255,0.09)" };
const thumb = 46, thumbGap = 6;

// Notes are written where they are read. They save themselves, so the page has no edit mode.
function Notes(p: { app: Library; focusedNote: Signal<InputRef | null>; fail: (message: string) => void; cover: (photo: Photo) => void; remove: (photo: Photo) => void }) {
  const title = signal(""), description = signal(""), date = signal(""), location = signal("");
  const saved = signal(false);
  let owner = "";
  let dirty = false;
  let pending: ReturnType<typeof setTimeout> | undefined;
  let badge: ReturnType<typeof setTimeout> | undefined;
  function commit() {
    clearTimeout(pending);
    if (!dirty || !owner) return;
    try {
      Photos.saveAnnotation(owner, title().trim(), description().trim(), date().trim(), location().trim());
      // A save that failed stays unsaved, so leaving the field or the next keystroke tries again.
      dirty = false;
      p.app.refresh();
      saved.set(true);
      clearTimeout(badge);
      badge = setTimeout(() => saved.set(false), 1800);
    } catch (e) { p.fail(String(e)); }
  }
  function edit(target: Signal<string>, value: string) {
    target.set(value);
    dirty = true;
    saved.set(false);
    clearTimeout(pending);
    pending = setTimeout(commit, 700);
  }
  const focused = p.focusedNote;
  effect(() => {
    const id = p.app.photoID(), photo = p.app.photo();
    untracked(() => {
      // The same photo can be annotated from the display window; follow it unless the user is typing here.
      if (id === owner && (dirty || focused())) return;
      if (id !== owner) { commit(); dirty = false; saved.set(false); }
      owner = id;
      title.set(photo?.title ?? ""); description.set(photo?.description ?? ""); date.set(photo?.date ?? ""); location.set(photo?.location ?? "");
    });
  });
  effect(() => {
    const input = focused();
    if (input) cleanup(keymap.bind({ escape: () => input.blur() }, { when: "always" }));
  });
  cleanup(() => { focused.set(null); commit(); clearTimeout(badge); });
  const bind = (input: () => InputRef | undefined) => ({ onFocus: () => focused.set(input() ?? null), onBlur: () => { focused.set(null); commit(); } });
  let titleInput: InputRef | undefined, dateInput: InputRef | undefined, placeInput: InputRef | undefined, storyInput: InputRef | undefined;
  const isCover = () => { const album = p.app.album(); return !!album && p.app.cover(album)?.id === p.app.photoID(); };
  const number = () => String(p.app.index() + 1).padStart(2, "0");
  return <View style={{ flex: 1, gap: 10 }}>
    <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", height: 16 }}>
      <Text style={{ color: onPhotoMuted, fontSize: 11, letterSpacing: 1.6 }}>{`${number()} / ${p.app.photos().length}`}</Text>
      <Text testID="note-saved" style={{ color: onPhotoMuted, fontSize: 11, opacity: saved() ? 1 : 0, ...fade }}>已保存</Text>
    </View>
    <Input testID="reader-title" accessibilityLabel="标题" placeholder="添加标题" value={title()} onChange={e => edit(title, e.value)} ref={r => (titleInput = r)} {...bind(() => titleInput)}
      style={{ ...field, height: 42, fontFamily: serif, fontSize: 25 }} hoverStyle={fieldHover} focusStyle={fieldFocus} />
    <View style={{ flexDirection: "row", alignItems: "center", gap: 14 }}>
      <Input testID="reader-date" accessibilityLabel="时间" placeholder="时间" value={date()} onChange={e => edit(date, e.value)} ref={r => (dateInput = r)} {...bind(() => dateInput)}
        style={{ ...field, width: 112, height: 28, fontSize: 12.5, color: onPhotoMuted }} hoverStyle={fieldHover} focusStyle={fieldFocus} />
      <Input testID="reader-location" accessibilityLabel="地点" placeholder="地点" value={location()} onChange={e => edit(location, e.value)} ref={r => (placeInput = r)} {...bind(() => placeInput)}
        style={{ ...field, flex: 1, height: 28, fontSize: 12.5, color: onPhotoMuted }} hoverStyle={fieldHover} focusStyle={fieldFocus} />
    </View>
    <View style={{ height: 0.5, backgroundColor: "rgba(255,255,255,0.16)" }} />
    <Input testID="reader-story" accessibilityLabel="旁注" placeholder={`写下${thisItem(p.app.photo())}的故事…`} multiline value={description()} onChange={e => edit(description, e.value)} ref={r => (storyInput = r)} {...bind(() => storyInput)}
      style={{ ...field, flex: 1, minHeight: 60, paddingVertical: 6, fontSize: 14.5, lineHeight: 23 }} hoverStyle={fieldHover} focusStyle={fieldFocus} />
    <View style={{ flexDirection: "row", gap: 8 }}>
      <Quiet id="photo-cover" label={isCover() ? "相册封面" : "设为封面"} disabled={isCover()} onPress={() => { const photo = p.app.photo(); if (photo) p.cover(photo); }} />
      <Quiet id="photo-remove" label="移除" danger onPress={() => { const photo = p.app.photo(); if (photo) p.remove(photo); }} />
    </View>
  </View>;
}

function Arrow(p: { id: string; label: string; icon: "previous" | "next"; shown: boolean; onPress: () => void }) {
  return <Button testID={p.id} accessibilityLabel={p.label} onPress={p.onPress}
    style={{ ...pill, ...fade, position: "absolute", top: "50%", marginTop: -19, [p.icon === "next" ? "right" : "left"]: 14, width: 38, height: 38, borderRadius: 19, alignItems: "center", justifyContent: "center", opacity: p.shown ? 1 : 0 }}
    hoverStyle={{ backgroundColor: "rgba(70,66,63,0.6)" }} activeStyle={{ opacity: 0.7 }} focusVisibleStyle={{ borderColor: "#9cc4fb", borderWidth: 2, opacity: 1 }}>
    <Icon name={p.icon} size={17} />
  </Button>;
}

// The photograph is the page: a print on a stage lit by its own colors, its notes beside it.
export function Reader(p: { app: Library; focusedNote: Signal<InputRef | null>; width: number; fail: (message: string) => void; cover: (photo: Photo) => void; remove: (photo: Photo) => void; menu: (photo: Photo, at: { x: number; y: number }) => void }) {
  const window = currentWindow();
  const room = signal({ width: 600, height: 400 });
  const shapes = signal(new Map<string, number>());
  const hovering = signal(false);
  const notesWidth = () => Math.max(250, Math.min(360, p.width * 0.3));
  const print = computed(() => {
    const ratio = shapes().get(p.app.photoID()) ?? 1.5;
    const w = Math.max(40, room().width - 124), h = Math.max(40, room().height - 44);
    return ratio > w / h ? { width: w, height: w / ratio } : { width: h * ratio, height: h };
  });
  let strip: ScrollRef | undefined;
  effect(() => {
    const at = p.app.index(), width = p.width;
    if (at >= 0) strip?.scrollTo({ x: Math.max(0, 16 + at * (thumb + thumbGap) + thumb / 2 - width / 2), animated: true });
  });
  const stripInset = () => Math.max(16, (p.width - p.app.photos().length * (thumb + thumbGap) + thumbGap) / 2);
  return <View testID="photo-reader" style={{ flex: 1, backgroundColor: stage }}>
    <If when={p.app.photo()?.url}><Image src={p.app.photo()?.url ?? ""} blurRadius={56} fadeDuration={420} style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, width: "100%", height: "100%", objectFit: "cover" }} /></If>
    <View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, backgroundImage: "linear-gradient(90deg, rgba(18,17,16,0.30) 0%, rgba(18,17,16,0.42) 55%, rgba(18,17,16,0.62) 100%)" }} />
    <View style={{ flex: 1, flexDirection: "row", paddingTop: 58 }}>
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }} onLayout={e => room.set(e.bounds.size)} onMouseEnter={() => hovering.set(true)} onMouseLeave={() => hovering.set(false)}>
        <View onContextMenu={e => { const photo = p.app.photo(); if (photo) p.menu(photo, e.pagePosition); }}
          style={{ width: print().width, height: print().height, borderRadius: 5, overflow: "hidden", backgroundColor: "rgba(0,0,0,0.25)", boxShadow: "0 22px 60px rgba(0,0,0,0.5), 0 2px 8px rgba(0,0,0,0.35)" }}>
          <If when={p.app.photo()?.url} else={<Artwork photo={p.app.photo()} />}>
            <Image src={p.app.photo()?.url ?? ""} accessibilityLabel={itemLabel(p.app.photo(), `${mediaName(p.app.photo())} ${p.app.index() + 1}`)} fadeDuration={200} style={{ width: "100%", height: "100%", objectFit: "contain" }}
              onLoad={e => { const id = p.app.photoID(); if (e.size.height > 0 && shapes().get(id) !== e.size.width / e.size.height) shapes.set(new Map(shapes()).set(id, e.size.width / e.size.height)); }} />
          </If>
          <If when={window.state()?.visible !== false}><MotionMedia photo={p.app.photo()} /></If>
        </View>
        <If when={p.app.index() > 0}><Arrow id="photo-previous" label="上一张" icon="previous" shown={hovering()} onPress={() => p.app.step(-1)} /></If>
        <If when={p.app.index() < p.app.photos().length - 1}><Arrow id="photo-next" label="下一张" icon="next" shown={hovering()} onPress={() => p.app.step(1)} /></If>
      </View>
      <View style={{ width: notesWidth(), paddingRight: 30, paddingLeft: 4, justifyContent: "center" }}>
        <View style={{ height: Math.min(room().height - 24, Math.max(print().height, 300)) }}><Notes app={p.app} focusedNote={p.focusedNote} fail={p.fail} cover={p.cover} remove={p.remove} /></View>
      </View>
    </View>
    <Scroll horizontal ref={r => (strip = r)} scrollbar={false} style={{ height: 70, flexGrow: 0 }} contentStyle={{ flexDirection: "row", alignItems: "center", gap: thumbGap, paddingHorizontal: stripInset(), paddingBottom: 6 }}>
      <Each of={p.app.photos()}>{item => <View onContextMenu={e => p.menu(item(), e.pagePosition)}>
        <Button accessibilityLabel={itemLabel(item(), `查看${thisItem(item())}`)} selected={item().id === p.app.photoID()} onPress={() => p.app.select(item().id)}
          style={{ ...fade, width: thumb, height: thumb, borderRadius: 7, overflow: "hidden", borderWidth: 2, borderColor: item().id === p.app.photoID() ? onPhoto : "transparent", opacity: item().id === p.app.photoID() ? 1 : 0.5 }}
          hoverStyle={{ opacity: 1 }} focusVisibleStyle={{ borderColor: "#9cc4fb", opacity: 1 }}>
          <Artwork photo={item()} />
        </Button>
      </View>}</Each>
    </Scroll>
  </View>;
}
