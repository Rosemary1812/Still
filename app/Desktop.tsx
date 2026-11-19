import { cleanup, computed, effect, Image, keymap, platform, signal, Text, View } from "nsh";
import { Dialog } from "nsh/base";
import { currentWindow, Tray, Window } from "nsh/desktop";
import { Photos } from "contactsheet/native";
import { Action, centered, ink, paper, row } from "./Controls";
import { makeLibrary, type Library } from "./DesktopState";
import { Gallery } from "./Gallery";
import { Annotation, Panels } from "./Panels";
import { Reading } from "./Reading";
import icon from "./assets/tray.svg";

function Display(p: { app: Library }) {
  const current = () => p.app.player().current ?? "";
  const photo = computed(() => p.app.library().photos.find(item => item.url === current()));
  const editing = signal("");
  const error = signal("");
  function edit() {
    const item = photo();
    if (!item) return;
    if (p.app.player().playing) p.app.control(Photos.toggle);
    error.set(""); editing.set(item.id);
  }
  const window = currentWindow();
  effect(() => {
    if (!window.state()?.focused || editing()) return;
    const unbind = keymap.bind({ left: () => p.app.control(Photos.previous), right: () => p.app.control(Photos.next), space: () => p.app.control(Photos.toggle) }, { when: "notEditing" });
    cleanup(unbind);
  });
  return <View style={{ flex: 1, backgroundColor: "#1b1a19" }}>
    <View style={centered}><If when={current()} else={<Text style={{ color: "#fff" }}>打开一本相册，开始放映。</Text>}><Image src={current()} style={{ width: "100%", height: "100%", objectFit: "contain" }} /></If></View>
    <If when={photo()}><View style={{ paddingHorizontal: 20, paddingTop: 12, gap: 4 }}>
      <If when={photo()?.title}><Text style={{ color: "#fff", fontFamily: "Georgia", fontSize: 21 }}>{photo()?.title}</Text></If>
      <If when={photo()?.description}><Text style={{ color: "#e9e8e5", fontSize: 14, numberOfLines: 3 }}>{photo()?.description}</Text></If>
      <If when={photo()?.date || photo()?.location}><Text style={{ color: "#c7c5bd", fontSize: 12 }}>{[photo()?.date, photo()?.location].filter(Boolean).join(" · ")}</Text></If>
    </View></If>
    <View style={{ ...row, padding: 12, justifyContent: "center" }}>
      <Action id="display-previous" label="上一张" disabled={!current()} onPress={() => p.app.control(Photos.previous)} />
      <Action id="display-toggle" label={p.app.player().playing ? "暂停" : "播放"} disabled={!current()} onPress={() => p.app.control(Photos.toggle)} />
      <Action id="display-next" label="下一张" disabled={!current()} onPress={() => p.app.control(Photos.next)} />
      <Action id="display-shuffle" label={p.app.player().shuffle ? "随机播放：开" : "随机播放：关"} onPress={() => p.app.control(() => Photos.setShuffle(!p.app.player().shuffle))} />
      <Text style={{ color: "#fff", fontSize: 13 }}>{`${p.app.player().paths.indexOf(current()) + 1} / ${p.app.player().paths.length}`}</Text>
      <If when={photo()}><Action id="display-edit" label="编辑描述" onPress={edit} /></If>
    </View>
    <If when={editing()}><Dialog accessibilityLabel="编辑放映照片" animation="none" onOpenChange={e => { if (!e.open) editing.set(""); }} style={{ width: 360, maxWidth: "92%", padding: 20, gap: 12, borderRadius: 16, backgroundColor: paper }}>
      <View style={{ ...row, justifyContent: "space-between" }}><Text style={{ color: ink, fontSize: 20 }}>编辑照片描述</Text><Action label="取消" onPress={() => editing.set("")} /></View>
      <Annotation photo={p.app.library().photos.find(item => item.id === editing())} save={(...values) => { try { Photos.saveAnnotation(editing(), ...values); p.app.refresh(); editing.set(""); } catch (e) { error.set(String(e)); } }} />
      <If when={error()}><Text style={{ color: "#903733" }}>{error()}</Text></If>
    </Dialog></If>
  </View>;
}
export function DesktopApp() {
  const main = currentWindow();
  const app = makeLibrary();
  if (platform.os === "macos") {
    effect(() => main.set({ titleBar: { style: app.reading() === "home" ? "hidden" : "default", height: 46 } }));
  }
  function display(albumID?: string) {
    app.command(() => { if (albumID) { Photos.playAlbum(albumID); app.player.set(Photos.snapshot()); } const Player = () => <Display app={app} />;
      Window.open(Player, { id: "display", title: "Still · 放映", defaultSize: { width: 660, height: 510 } }).focus(); });
  }
  main.on("closePress", () => main.hide());
  const poll = setInterval(() => { const next = Photos.snapshot(); if (next.revision !== app.player().revision) app.player.set(next); },250);
  cleanup(() => clearInterval(poll));
  effect(() => { Tray.set({ icon, tooltip: app.player().playing ? "Still · 播放中" : "Still", onClick: () => main.focus(), menu: [
    { label: "显示相册", onSelect: () => main.focus() }, { label: "打开放映窗口", onSelect: () => display() }, { label: "选择放映相册", disabled: !app.library().albums.some(a => a.photoIds.length > 0), submenu: app.library().albums.map(a => ({ label: a.name, disabled: !a.photoIds.length, onSelect: () => display(a.id) })) }, { type: "separator" },
    { label: app.player().playing ? "暂停" : "播放", onSelect: () => app.control(Photos.toggle) }, { label: "下一张", onSelect: () => app.control(Photos.next) }, {type: "separator"}, {role: "quit"}
  ] }); });
  cleanup(() => Tray.set(null));
  return <View style={{ flex: 1 }}><If when={app.reading() === "home"} else={<Reading app={app} display={() => display(app.albumID())} />}><Gallery app={app} /></If>
    <Panels app={app} /><If when={app.error() && app.panel() === "none"}><View style={{ ...row, padding: 10, backgroundColor: "#f8e4e1" }}><Text style={{ flex: 1, color: "#863a30" }}>{app.error()}</Text><Action label="关闭" onPress={() => app.error.set("")} /></View></If>
  </View>;
}
