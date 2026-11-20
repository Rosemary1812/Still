import { signal, Text, View } from "nsh";
import { Dialog } from "nsh/base";
import { Photos } from "contactsheet/native";
import { Action, Field, ink, paper, row } from "./Controls";
import type { Library, Panel, Photo } from "./DesktopState";

const titles: Record<Panel,string> = { none: "", create: "新建相册" };
function AlbumName(p: { app: Library }) {
  const draft = signal("");
  // A new album opens on its own empty page, which offers every way to fill it.
  const save = () => p.app.command(() => { const id = Photos.createAlbum(draft()); p.app.refresh(); p.app.openAlbum(id); });
  return <View style={{ gap: 16 }}><Field label="相册名称" id="album-name" value={draft()} change={v => draft.set(v)} placeholder="为相册起个名字" /><Action primary id="save-album" label="创建相册" disabled={!draft().trim()} onPress={save} /></View>;
}
export function Annotation(p: { photo?: Photo; save: (title: string, description: string, date: string, location: string) => void }) {
  const original = p.photo;
  const title = signal(original?.title ?? ""), description = signal(original?.description ?? ""), date = signal(original?.date ?? ""), location = signal(original?.location ?? "");
  return <View style={{ gap: 10 }}><Field id="note-title" label="标题" value={title()} change={v => title.set(v)} /><Field id="note-description" label="描述" multiline value={description()} change={v => description.set(v)} /><Field id="note-date" label="日期" placeholder="YYYY-MM-DD" value={date()} change={v => date.set(v)} /><Field id="note-location" label="地点" value={location()} change={v => location.set(v)} /><Action primary label="保存描述" onPress={() => p.save(title(), description(), date(), location())} /></View>;
}
export function Panels(p: { app: Library }) {
  const close = () => { if (!p.app.busy()) { p.app.panel.set("none"); p.app.error.set(""); } };
  return <If when={p.app.panel() !== "none"}><Dialog testID="album-panel" accessibilityLabel={titles[p.app.panel()]} animation="none" onOpenChange={event => { if (!event.open) close(); }} closeOnEscape={!p.app.busy()} closeOnBackdropPress={!p.app.busy()}
    backdropStyle={{ backgroundColor: "rgba(27,26,24,0.22)" }} style={{ width: 380, maxWidth: "92%", padding: 23, gap: 18, borderRadius: 17, backgroundColor: paper, boxShadow: "0 12px 38px rgba(0,0,0,0.22)" }}>
    <View style={{ ...row, justifyContent: "space-between" }}><Text style={{ fontSize: 22, color: ink, fontFamily: "Georgia" }}>{titles[p.app.panel()]}</Text><Action label="完成" id="close-panel" disabled={p.app.busy()} onPress={close} /></View>
    <If when={p.app.panel() === "create"}><AlbumName app={p.app} /></If>
    <If when={p.app.error()}><Text style={{ color: "#903733", fontSize: 13 }}>{p.app.error()}</Text></If>
  </Dialog></If>;
}
