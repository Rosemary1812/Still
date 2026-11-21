import { cleanup, keymap, signal, Text, View, type TextStyle, type ViewStyle } from "nsh";
import { Button, Dialog, Input } from "nsh/base";
import { Photos } from "contactsheet/native";
import { ink, muted } from "./Controls";
import type { Library, Photo } from "./DesktopState";

// The measures of the system's own alert on macOS 26, the one AlertDialog shows for a removal: a 260-point
// glass card, text at 13 and capsule buttons of equal width. `margin: "auto"` centres the card: a dialog is
// a bare layer over the window and places its popup top-left.
export const card: ViewStyle = {
  margin: "auto", width: 260, maxWidth: "92%", paddingHorizontal: 16, paddingTop: 20, paddingBottom: 16, gap: 12, borderRadius: 26,
  glassEffect: "regular", backdropFilter: "blur(30px)", backgroundColor: "rgba(246,246,246,0.78)",
  borderWidth: 0.5, borderColor: "rgba(255,255,255,0.7)", boxShadow: "0 12px 44px rgba(0,0,0,0.26)",
};
export const dim: ViewStyle = { backgroundColor: "rgba(0,0,0,0.2)" };
const accent = "#0a84ff", ring = "rgba(10,132,255,0.5)";
const body: TextStyle = { color: ink, fontSize: 13, lineHeight: 17 };
const field = { height: 26, color: ink, fontSize: 13, paddingHorizontal: 7, borderRadius: 6, borderWidth: 1, borderColor: "rgba(0,0,0,0.14)", backgroundColor: "#fff", caretColor: accent };
const focused: ViewStyle = { outlineWidth: 3, outlineColor: ring };
export function Heading(p: { title: string; message?: string }) {
  return <View style={{ gap: 6 }}><Text style={{ ...body, fontWeight: "700" }}>{p.title}</Text><If when={p.message}><Text style={body}>{p.message}</Text></If></View>;
}
function Choice(p: { label: string; onPress: () => void; id?: string; disabled?: boolean; primary?: boolean }) {
  return <Button testID={p.id} accessibilityLabel={p.label} disabled={p.disabled} onPress={p.onPress}
    style={{ flex: 1, height: 28, borderRadius: 14, alignItems: "center", justifyContent: "center", backgroundColor: p.primary && !p.disabled ? accent : "rgba(0,0,0,0.08)" }}
    hoverStyle={{ opacity: 0.88 }} activeStyle={{ opacity: 0.72 }} focusVisibleStyle={focused}>
    <Text style={{ color: p.disabled ? "rgba(0,0,0,0.28)" : p.primary ? "#fff" : ink, fontSize: 13, fontWeight: "500" }}>{p.label}</Text>
  </Button>;
}
// The focused field would otherwise spend the first Escape on giving up the focus.
function Choices(p: { cancel: () => void; confirm: () => void; label: string; id?: string; disabled?: boolean; busy?: boolean }) {
  cleanup(keymap.bind({ escape: p.cancel }, { when: "always" }));
  return <View style={{ flexDirection: "row", gap: 8, marginTop: 4 }}>
    <Choice label="取消" id="close-panel" disabled={p.busy} onPress={p.cancel} />
    <Choice primary id={p.id} label={p.label} disabled={p.disabled || p.busy} onPress={p.confirm} />
  </View>;
}
function AlbumName(p: { app: Library; close: () => void }) {
  const draft = signal("");
  // A new album opens on its own empty page, which offers every way to fill it.
  const save = () => { if (draft().trim()) p.app.command(() => { const id = Photos.createAlbum(draft()); p.app.refresh(); p.app.openAlbum(id); }); };
  return <>
    <Input testID="album-name" accessibilityLabel="相册名称" autoFocus placeholder="名称" value={draft()} onChange={e => draft.set(e.value)} onSubmit={save} style={field} focusStyle={focused} />
    <If when={p.app.error()}><Text style={{ color: "#c0392b", fontSize: 12 }}>{p.app.error()}</Text></If>
    <Choices cancel={p.close} confirm={save} id="save-album" label="创建" disabled={!draft().trim()} busy={p.app.busy()} />
  </>;
}
function Line(p: { label: string; value: string; change: (s: string) => void; id: string; multiline?: boolean; placeholder?: string }) {
  return <View style={{ gap: 4 }}><Text style={{ color: muted, fontSize: 11 }}>{p.label}</Text><Input testID={p.id} accessibilityLabel={p.label} placeholder={p.placeholder} value={p.value} onChange={e => p.change(e.value)} multiline={p.multiline} style={{ ...field, height: p.multiline ? 64 : 26 }} focusStyle={focused} /></View>;
}
export function Annotation(p: { photo?: Photo; save: (title: string, description: string, date: string, location: string) => void; cancel: () => void }) {
  const original = p.photo;
  const title = signal(original?.title ?? ""), description = signal(original?.description ?? ""), date = signal(original?.date ?? ""), location = signal(original?.location ?? "");
  return <>
    <Line id="note-title" label="标题" value={title()} change={v => title.set(v)} /><Line id="note-description" label="描述" multiline value={description()} change={v => description.set(v)} /><Line id="note-date" label="日期" placeholder="YYYY-MM-DD" value={date()} change={v => date.set(v)} /><Line id="note-location" label="地点" value={location()} change={v => location.set(v)} />
    <Choices cancel={p.cancel} confirm={() => p.save(title(), description(), date(), location())} label="保存" />
  </>;
}
export function Panels(p: { app: Library }) {
  const close = () => { if (!p.app.busy()) { p.app.panel.set("none"); p.app.error.set(""); } };
  return <If when={p.app.panel() === "create"}><Dialog testID="album-panel" accessibilityLabel="新建相册" animation="fade" onOpenChange={event => { if (!event.open) close(); }} closeOnEscape={!p.app.busy()} closeOnBackdropPress={!p.app.busy()} backdropStyle={dim} style={card}>
    <Heading title="新建相册" message="为这本相册输入名称。" />
    <AlbumName app={p.app} close={close} />
  </Dialog></If>;
}
