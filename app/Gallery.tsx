import { computed, Image, Scroll, signal, Text, View, type ViewStyle } from "nsh";
import { Menu } from "nsh/desktop";
import { Button } from "nsh/base";
import { Action, centered, GlassButton, GlassTint, Hint, glass, ink, muted, row } from "./Controls";
import type { Album, Library, Photo } from "./DesktopState";

export function Artwork(p: { photo?: Photo; fit?: "contain" | "cover"; light?: boolean }) {
  const failed = signal("");
  return <View style={{ width: "100%", height: "100%", alignItems: "center", justifyContent: "center", overflow: "hidden", backgroundColor: p.light ? "#e6e2da" : "#343332" }}>
    <If when={p.photo?.url && p.photo.url !== failed()} else={<Text style={{ color: p.light ? muted : "#c6c2bb", fontSize: 12 }}>{p.photo ? "照片不可用" : "Still"}</Text>}><Image src={p.photo?.url ?? ""} style={{ width: "100%", height: "100%", objectFit: p.fit ?? "cover" }} onError={() => failed.set(p.photo?.url ?? "")} /></If>
  </View>;
}
export function Switcher(p: { app: Library; prefix: string }) {
  return <View style={{ ...row, ...glass, padding: 3, gap: 1 }}><GlassTint />
    <GlassButton label="相册墙" icon="grid" id={`${p.prefix}-wall`} segment selected={p.app.library().viewMode === "wall"} onPress={() => p.app.changeView("wall")} />
    <GlassButton label="唱片柜" icon="cabinet" id={`${p.prefix}-cabinet`} segment selected={p.app.library().viewMode === "cabinet"} onPress={() => p.app.changeView("cabinet")} />
  </View>;
}
const metal: ViewStyle = { height: 11, backgroundColor: "#686764", backgroundImage: "linear-gradient(180deg, #d7dad8 0%, #8b8c87 30%, #383936 54%, #a6a59f 80%, #454542 100%)", borderRadius: 2, borderColor: "#292a27", borderWidth: 1 };
function albumMenu(app: Library, album: Album, at?: { x: number; y: number }) {
  return Menu.popup([
    { label: "打开相册", onSelect: () => app.openAlbum(album.id) },
    { label: "查看详情", onSelect: () => app.inspect(album.id) }
  ], at);
}
function Spine(p: { app: Library; album: Album }) {
  return <View onContextMenu={e => albumMenu(p.app,p.album,e.pagePosition)}><Button testID={`album-${p.album.id}`} accessibilityLabel={`${p.album.name}，${p.album.photoIds.length} 张照片`} tooltip={<Hint label={p.album.name} />} onPress={() => p.app.inspect(p.album.id)}
    style={{ width: 33, height: 301, padding: 2, gap: 1, borderRadius: 3, borderWidth: 1, borderColor: "#20211e", backgroundColor: "#52534e", boxShadow: "3px 3px 4px rgba(0,0,0,0.22)" }}
    hoverStyle={{ transform: "translateY(-9px)" }} focusVisibleStyle={{ borderColor: "#81aff0", borderWidth: 2 }}>
    <View style={metal} /><View style={{ flex: 1 }}><Artwork photo={p.app.cover(p.album)} /></View><View style={metal} />
  </Button></View>;
}
function Cabinet(p: { app: Library; width: number }) {
  const shelves = computed(() => { const all = p.app.library().albums; const cap = Math.max(1, Math.floor((p.width - 122) / 41)); return Array.from({length: Math.ceil(all.length / cap)}, (_, i) => all.slice(i * cap, (i + 1) * cap)); });
  return <Scroll testID="gallery-cabinet" style={{ flex: 1 }} contentStyle={{ paddingHorizontal: 32, paddingTop: 82, paddingBottom: 50, gap: 1 }}>
    <Each of={shelves()}>{shelf => <View style={{ backgroundColor: "#dadbd9", boxShadow: "0 9px 17px rgba(0,0,0,0.20)" }}>
      <View style={{ height: 8, backgroundColor: "#fafaf9" }} />
      <View style={{ flexDirection: "row", height: 338, borderLeftWidth: 10, borderRightWidth: 10, borderColor: "#f1f1ef", backgroundImage: "linear-gradient(180deg, #aaaaa8 0%, #c8c9c7 13%, #e3e3e1 100%)", paddingHorizontal: 18, alignItems: "flex-end", gap: 8 }}>
        <Each of={shelf()}>{a => <Spine app={p.app} album={a()} />}</Each>
      </View><View style={{ height: 13, backgroundImage: "linear-gradient(180deg, #e9e9e7 0%, #ffffff 55%, #d8d9d6 100%)" }} />
    </View>}</Each>
  </Scroll>;
}
function Wall(p: { app: Library; width: number }) {
  const side = () => p.width / Math.max(2, Math.floor(p.width / 158));
  return <Scroll testID="gallery-wall" style={{ flex: 1 }} contentStyle={{ flexDirection: "row", flexWrap: "wrap", alignContent: "flex-start" }}>
    <Each of={p.app.library().albums}>{a => <View onContextMenu={e => albumMenu(p.app,a(),e.pagePosition)}><Button testID={`album-${a().id}`} accessibilityLabel={`${a().name}，${a().photoIds.length} 张照片`} onPress={() => p.app.inspect(a().id)} style={{ width: side(), height: side(), overflow: "hidden" }}>
      <Artwork photo={p.app.cover(a())} /><View style={{ position: "absolute", bottom: 0, left: 0, right: 0, paddingHorizontal: 10, paddingBottom: 9, paddingTop: 26, backgroundImage: "linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.65) 100%)" }}><Text style={{ color: "#fff", fontSize: 13, numberOfLines: 1 }}>{a().name}</Text></View>
    </Button></View>}</Each>
  </Scroll>;
}
export function Gallery(p: { app: Library }) {
  const width = signal(920);
  return <View style={{ flex: 1, backgroundColor: "#f8f8f7" }} onLayout={e => width.set(Math.max(200,e.bounds.size.width))}>
    <If when={p.app.library().albums.length > 0} else={<View style={centered}><Text style={{ color: ink, fontSize: 24, fontFamily: "Georgia" }}>创建第一本相册</Text><Text style={{ color: muted, fontSize: 14 }}>把照片和旁边的故事收在一起。</Text><Action label="新建相册" onPress={() => p.app.panel.set("create")} /></View>}>
      <If when={p.app.library().viewMode === "wall"} else={<Cabinet app={p.app} width={width()} />}><Wall app={p.app} width={width()} /></If>
    </If>
    <View style={{ ...row, position: "absolute", top: 15, left: 24, right: 24, justifyContent: "space-between", pointerEvents: "box-none" }}>
      <View style={{ flex: 1, alignItems: "flex-start", pointerEvents: "none" }}><Text style={{ fontSize: 24, fontWeight: "700", fontFamily: "Georgia", color: p.app.library().viewMode === "wall" && p.app.library().albums.length ? "#fff" : ink }}>Still</Text></View>
      <Switcher app={p.app} prefix="home" />
      <View style={{ ...row, flex: 1, justifyContent: "flex-end", pointerEvents: "box-none" }}><GlassButton icon="settings" id="home-settings" label="设置" onPress={() => p.app.panel.set("settings")} /><GlassButton icon="plus" id="home-add" label="添加相册" onPress={() => p.app.panel.set("create")} /></View>
    </View>
  </View>;
}
