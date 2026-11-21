import { cleanup, keymap, signal, Text, View, type ViewStyle } from "nsh";
import { Dialog, Input } from "nsh/base";
import { Photos } from "contactsheet/native";
import { Action, Field, ink, paper, row } from "./Controls";
import type { Library, Photo } from "./DesktopState";

function AlbumName(p: { app: Library; close: () => void }) {
  const draft = signal("");
  // The focused name field would otherwise spend the first Escape on giving up the focus.
  cleanup(keymap.bind({ escape: p.close }, { when: "always" }));
  // A new album opens on its own empty page, which offers every way to fill it.
  const save = () => { if (draft().trim()) p.app.command(() => { const id = Photos.createAlbum(draft()); p.app.refresh(); p.app.openAlbum(id); }); };
  return <View style={{ gap: 16 }}>
    <Input testID="album-name" accessibilityLabel="相册名称" autoFocus placeholder="为相册起个名字" value={draft()} onChange={e => draft.set(e.value)} onSubmit={save}
      style={{ height: 36, color: ink, fontSize: 14, paddingHorizontal: 10, borderRadius: 8, borderWidth: 1, borderColor: "#cbc8bf", backgroundColor: "#fff" }} />
    <If when={p.app.error()}><Text style={{ color: "#903733", fontSize: 13 }}>{p.app.error()}</Text></If>
    <View style={{ ...row, justifyContent: "flex-end" }}>
      <Action label="取消" id="close-panel" disabled={p.app.busy()} onPress={p.close} />
      <Action primary id="save-album" label="创建" disabled={!draft().trim() || p.app.busy()} onPress={save} />
    </View>
  </View>;
}
export function Annotation(p: { photo?: Photo; save: (title: string, description: string, date: string, location: string) => void }) {
  const original = p.photo;
  const title = signal(original?.title ?? ""), description = signal(original?.description ?? ""), date = signal(original?.date ?? ""), location = signal(original?.location ?? "");
  return <View style={{ gap: 10 }}><Field id="note-title" label="标题" value={title()} change={v => title.set(v)} /><Field id="note-description" label="描述" multiline value={description()} change={v => description.set(v)} /><Field id="note-date" label="日期" placeholder="YYYY-MM-DD" value={date()} change={v => date.set(v)} /><Field id="note-location" label="地点" value={location()} change={v => location.set(v)} /><Action primary label="保存描述" onPress={() => p.save(title(), description(), date(), location())} /></View>;
}
// `margin: "auto"` centres the card: a dialog is a bare layer over the window and places its popup top-left.
export const card: ViewStyle = { margin: "auto", maxWidth: "92%", borderRadius: 16, backgroundColor: paper, boxShadow: "0 18px 50px rgba(0,0,0,0.28)" };
export function Panels(p: { app: Library }) {
  const close = () => { if (!p.app.busy()) { p.app.panel.set("none"); p.app.error.set(""); } };
  return <If when={p.app.panel() === "create"}><Dialog testID="album-panel" accessibilityLabel="新建相册" animation="none" onOpenChange={event => { if (!event.open) close(); }} closeOnEscape={!p.app.busy()} closeOnBackdropPress={!p.app.busy()}
    backdropStyle={{ backgroundColor: "rgba(27,26,24,0.28)" }} style={{ ...card, width: 340, padding: 22, gap: 16 }}>
    <Text style={{ fontSize: 19, color: ink, fontFamily: "Georgia" }}>新建相册</Text>
    <AlbumName app={p.app} close={close} />
  </Dialog></If>;
}
