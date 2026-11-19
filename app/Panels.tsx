import { platform, signal, Text, View } from "nsh";
import { Dialog } from "nsh/base";
import { Photos } from "contactsheet/native";
import { Action, Field, ink, muted, paper, row } from "./Controls";
import { Switcher } from "./Gallery";
import type { Library, Panel, Photo } from "./DesktopState";

const titles: Record<Panel,string> = { none: "", settings: "设置", create: "新建相册", import: "导入照片", manage: "相册操作", edit: "照片描述", rename: "重命名相册", remove: "移除照片", delete: "删除相册" };
function AlbumName(p: { app: Library; create: boolean }) {
  const draft = signal(p.create ? "" : p.app.album()?.name ?? "");
  function save() {
    if (p.create) p.app.command(() => { const id = Photos.createAlbum(draft()); p.app.refresh(); p.app.openAlbum(id); p.app.panel.set("import"); });
    else p.app.mutate(() => Photos.renameAlbum(p.app.albumID(),draft()));
  }
  return <View style={{ gap: 16 }}><Field label="相册名称" id="album-name" value={draft()} change={v => draft.set(v)} placeholder="为相册起个名字" /><Action primary id="save-album" label={p.create ? "创建相册" : "保存名称"} disabled={!draft().trim()} onPress={save} /></View>;
}
export function Annotation(p: { photo?: Photo; save: (title: string, description: string, date: string, location: string) => void }) {
  const original = p.photo;
  const title = signal(original?.title ?? ""), description = signal(original?.description ?? ""), date = signal(original?.date ?? ""), location = signal(original?.location ?? "");
  return <View style={{ gap: 10 }}><Field id="note-title" label="标题" value={title()} change={v => title.set(v)} /><Field id="note-description" label="描述" multiline value={description()} change={v => description.set(v)} /><Field id="note-date" label="日期" placeholder="YYYY-MM-DD" value={date()} change={v => date.set(v)} /><Field id="note-location" label="地点" value={location()} change={v => location.set(v)} /><Action primary label="保存描述" onPress={() => p.save(title(), description(), date(), location())} /></View>;
}
export function Panels(p: { app: Library }) {
  const close = () => { if (!p.app.busy()) { p.app.panel.set("none"); p.app.error.set(""); } };
  const albumName = () => p.app.album()?.name ?? "";
  return <If when={p.app.panel() !== "none"}><Dialog testID="album-panel" accessibilityLabel={titles[p.app.panel()]} animation="none" onOpenChange={event => { if (!event.open) close(); }} closeOnEscape={!p.app.busy()} closeOnBackdropPress={!p.app.busy()}
    backdropStyle={{ backgroundColor: "rgba(27,26,24,0.22)" }} style={{ width: 380, maxWidth: "92%", padding: 23, gap: 18, borderRadius: 17, backgroundColor: paper, boxShadow: "0 12px 38px rgba(0,0,0,0.22)" }}>
    <View style={{ ...row, justifyContent: "space-between" }}><Text style={{ fontSize: 22, color: ink, fontFamily: "Georgia" }}>{titles[p.app.panel()]}</Text><Action label="完成" id="close-panel" disabled={p.app.busy()} onPress={close} /></View>
    <If when={p.app.panel() === "settings"}><View style={{ alignItems: "flex-start", gap: 12 }}><Text style={{ color: ink }}>相册主页视图</Text><Switcher app={p.app} prefix="settings" /><Text style={{ color: muted, fontSize: 12 }}>{p.app.library().viewMode === "wall" ? "当前：相册墙" : "当前：唱片柜"}</Text></View></If>
    <If when={p.app.panel() === "create"}><AlbumName app={p.app} create /></If>
    <If when={p.app.panel() === "rename"}><AlbumName app={p.app} create={false} /></If>
    <If when={p.app.panel() === "import"}><View style={{ gap: 9 }}><Text style={{ color: muted }}>{`添加到「${albumName()}」`}</Text><Action label="从文件选择" disabled={p.app.busy()} onPress={() => p.app.addPhotos("files")} /><If when={platform.os === "macos"}><Action label="从 Apple 照片选择" disabled={p.app.busy()} onPress={() => p.app.addPhotos("apple")} /></If><If when={p.app.busy()}><Text style={{ color: muted }}>正在导入…</Text></If></View></If>
    <If when={p.app.panel() === "manage"}><View style={{ gap: 8 }}><Text style={{ color: muted }}>{albumName()}</Text><Action label="重命名相册" onPress={() => p.app.panel.set("rename")} /><Action label="删除相册" danger onPress={() => p.app.panel.set("delete")} /></View></If>
    <If when={p.app.panel() === "delete"}><View style={{ gap: 14 }}><Text style={{ color: ink }}>{`删除「${albumName()}」？原始照片将保留。`}</Text><Action label="确认删除相册" danger onPress={() => p.app.mutate(() => Photos.deleteAlbum(p.app.albumID()), p.app.home)} /></View></If>
    <If when={p.app.panel() === "remove"}><View style={{ gap: 14 }}><Text style={{ color: ink }}>从这本相册移除照片？原始照片将保留。</Text><Action label="确认移除照片" danger onPress={p.app.remove} /></View></If>
    <If when={p.app.panel() === "edit"}><Annotation photo={p.app.photo()} save={(...values) => p.app.mutate(() => Photos.saveAnnotation(p.app.photoID(), ...values))} /></If>
    <If when={p.app.error()}><Text style={{ color: "#903733", fontSize: 13 }}>{p.app.error()}</Text></If>
  </Dialog></If>;
}
