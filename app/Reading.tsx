import { cleanup, computed, effect, keymap, PanResponder, reduceMotion, Scroll, signal, Text, View } from "nsh";
import { Photos } from "contactsheet/native";
import { Button } from "nsh/base";
import { Action, centered, glass, ink, muted, paper, row } from "./Controls";
import { Artwork } from "./Gallery";
import type { Library } from "./DesktopState";

function PhotoWall(p: { app: Library; width: number; height: number; paused: boolean }) {
  const phase = signal(0);
  const offset = signal(0);
  const dragging = signal(false);
  let origin = 0;
  let last = Date.now();
  const clock = setInterval(() => {
    const now = Date.now();
    if (!p.paused && !dragging()) phase.set(phase() + Math.min(now - last, 100) / 17000);
    last = now;
  }, 50);
  cleanup(() => clearInterval(clock));
  const edge = () => Math.max(20, Math.ceil(p.height / 4));
  const cells = computed(() => Array.from({ length: Math.ceil(p.width / edge()) + 2 }, (_, i) => i));
  const progress = () => phase() + offset();
  const offsets = [151, 296, 62, 207].map(x => 1 - x / 379.5);
  const position = (r: number) => progress() + offsets[r];
  const drag = PanResponder.create({
    onMoveShouldSetPanResponderCapture: (_, g) => Math.abs(g.dx) > 8 && Math.abs(g.dx) > Math.abs(g.dy),
    onPanResponderGrant: () => { dragging.set(true); origin = offset(); },
    onPanResponderMove: (_, g) => offset.set(origin - g.dx / edge()),
    onPanResponderRelease: (_, g) => { offset.set(origin - g.dx / edge()); dragging.set(false); },
    onPanResponderTerminate: () => dragging.set(false),
  });

  const whole = [0, 1, 2, 3].map(r => computed(() => Math.floor(position(r))));
  const index = (r: number, x: number) => { const n = p.app.photos().length;
    if (r >= n) return r % n;
    const period = Math.ceil((n - r) / 4);
    return r + 4 * (((x + whole[r]()) % period + period) % period); };
  const at = (r: number, x: number) => p.app.photos()[index(r, x)];
  return <View testID="photo-wall" style={{ flex: 1, overflow: "hidden" }} {...drag.panHandlers}>
    <Each of={[0,1,2,3]}>{r => <View style={{ flexDirection: "row", height: edge(), flexShrink: 0, transform: [{ translateX: -(position(r()) - Math.floor(position(r()))) * edge() }] }}>
      <Each of={cells()}>{x => <Button accessibilityLabel={at(r(), x())?.title || `查看照片 ${1 + index(r(),x())}`} onPress={() => { const photo = at(r(), x()); if (photo) p.app.select(photo.id, "preview"); }} style={{ height: edge(), width: edge(), flexShrink: 0 }}><Artwork photo={at(r(), x())} /></Button>}</Each>
    </View>}</Each>
  </View>;
}
function Reader(p: { app: Library }) {
  const book = () => p.app.reading() === "book";
  return <View style={{ flex: 1, paddingTop: 73, paddingHorizontal: 24, paddingBottom: 17, gap: 14, backgroundColor: book() ? "#e7e5df" : paper }}>
    <View style={{ flex: 1, flexDirection: "row", backgroundColor: book() ? "#fcfbf7" : paper, padding: book() ? 16 : 0, boxShadow: book() ? "0 4px 14px rgba(0,0,0,0.15)" : "none" }}>
      <View style={{ flex: book() ? 1 : 2, overflow: "hidden", backgroundColor: "#e4e1dc" }}><Artwork photo={p.app.photo()} fit="contain" light /></View>
      <Scroll style={{ flex: 1 }} contentStyle={{ padding: 22, gap: 12 }}>
        <Text style={{ color: muted, fontSize: 11, letterSpacing: 1.2 }}>{`${p.app.album()?.name ?? ""}  /  ${p.app.index() + 1}`}</Text>
        <Text style={{ color: ink, fontSize: 24, fontFamily: "Georgia" }}>{p.app.photo()?.title || "未命名照片"}</Text>
        <If when={p.app.photo()?.date}><Text style={{ color: muted, fontSize: 12 }}>{p.app.photo()?.date}</Text></If>
        <If when={p.app.photo()?.location}><Text style={{ color: muted, fontSize: 12 }}>{p.app.photo()?.location}</Text></If>
        <Text style={{ color: ink, fontSize: 15, lineHeight: 23 }}>{p.app.photo()?.description || "为这张照片写下第一段回忆。"}</Text>
        <View style={{ alignItems: "flex-start", gap: 6 }}><Action label="编辑描述" onPress={() => p.app.panel.set("edit")} /><Action label={p.app.album()?.coverId === p.app.photoID() ? "当前相册封面" : "设为相册封面"} disabled={p.app.album()?.coverId === p.app.photoID()} onPress={() => p.app.mutate(() => Photos.setCover(p.app.albumID(), p.app.photoID()))} /><Action label="从相册移除" danger onPress={() => p.app.panel.set("remove")} /></View>
      </Scroll>
    </View>
    <If when={!book()}><Scroll horizontal style={{ height: 52, flexGrow: 0 }} contentStyle={{ flexDirection: "row", gap: 6 }}><Each of={p.app.photos()}>{item => <Button accessibilityLabel={item().title || "查看缩略图"} selected={item().id === p.app.photoID()} onPress={() => p.app.select(item().id,"preview")} style={{ width: 52, height: 52, borderWidth: 2, borderColor: item().id === p.app.photoID() ? "#477cab" : "transparent" }}><Artwork photo={item()} /></Button>}</Each></Scroll></If>
    <View style={{ ...row, justifyContent: "space-between" }}><Action label={book() ? "← 上一页" : "← 上一张"} disabled={p.app.index() <= 0} onPress={() => p.app.step(-1)} /><Text style={{ color: muted }}>{`${p.app.index()+1} / ${p.app.photos().length}`}</Text><Action label={book() ? "下一页 →" : "下一张 →"} disabled={p.app.index() >= p.app.photos().length - 1} onPress={() => p.app.step(1)} /></View>
  </View>;
}
export function Reading(p: { app: Library; display: () => void }) {
  const paused = signal(reduceMotion());
  effect(() => paused.set(reduceMotion()));
  effect(() => {
    if (p.app.panel() !== "none") return;
    const clear = keymap.bind({
      escape: () => p.app.reading() === "wall" ? p.app.home() : p.app.reading.set("wall"),
      left: () => { if (p.app.reading() !== "wall") p.app.step(-1); },
      right: () => { if (p.app.reading() !== "wall") p.app.step(1); }
    }, { when: "notEditing" });
    cleanup(clear);
  });

  const width = signal(900), height = signal(600);
  return <View style={{ flex: 1, backgroundColor: paper }} onLayout={e => { width.set(e.bounds.size.width); height.set(e.bounds.size.height); }}>
    <If when={p.app.photos().length > 0} else={<View style={centered}><Text style={{ color: ink, fontSize: 23 }}>{p.app.album()?.name}</Text><Text style={{ color: muted }}>相册里还没有照片</Text><Action label="导入照片" primary onPress={() => p.app.panel.set("import")} /></View>}>
      <If when={p.app.reading() === "wall"} else={<Reader app={p.app} />}><PhotoWall app={p.app} width={width()} height={height()} paused={paused() || p.app.panel() !== "none"} /></If>
    </If>
    <View style={{ position: "absolute", top: 13, left: 14, right: 14, alignItems: "center", pointerEvents: "box-none" }}><View style={{ ...row, ...glass, gap: 4, padding: 4, flexWrap: "wrap", justifyContent: "center" }}>
      <Action label="‹ 全部相册" onPress={p.app.home} /><Action label="照片墙" primary={p.app.reading() === "wall"} onPress={() => p.app.reading.set("wall")} /><Action label="翻阅" disabled={!p.app.photos().length} primary={p.app.reading() === "book"} onPress={() => { const photo = p.app.photo() ?? p.app.photos()[0]; if (photo) p.app.select(photo.id,"book"); }} />
      <If when={p.app.reading() === "wall" && p.app.photos().length > 0}><Action label={paused() ? "继续流动" : "暂停流动"} onPress={() => paused.set(!paused())} /></If>
      <Action label="＋ 照片" onPress={() => p.app.panel.set("import")} /><Action label="放映" disabled={!p.app.photos().length} onPress={p.display} /><Action label="更多" onPress={() => p.app.panel.set("manage")} />
    </View></View>
  </View>;
}
