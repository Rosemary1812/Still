import { cleanup, computed, createAnimatedValue, effect, Image, keymap, platform, reduceMotion, Scroll, signal, Text, untracked, View, type MouseEvent, type TransformStep, type ViewRef, type ViewStyle } from "nsh";
import { Menu } from "nsh/desktop";
import { Button } from "nsh/base";
import { camera, carry, closeUp, dropMs, hop, inQuart, introMs, lean, liftMs, out, outQuart, pull, pullMs, recline, rise, settle, spine, spineSpring, staggerMs, takeMs, thickness } from "./AlbumMotion";
import { Action, centered, GlassButton, Hint, toolbarGlass, ink, muted, row } from "./Controls";
import type { Album, Library, Photo } from "./DesktopState";

type Rect = { x: number; y: number; width: number; height: number };
/** An album taken from its place into the detail view. `place` is where it stands, and stands again once put back. */
type Flight = { album: Album; spine: boolean; from: Rect; tilt: number; place: () => Promise<Rect | undefined>; landed: () => void };
type Stage = { entering: () => boolean; ready: () => boolean; held: () => string; inspect: (flight: Flight) => void };

export function Artwork(p: { photo?: Photo; fit?: "contain" | "cover"; light?: boolean }) {
  const failed = signal("");
  return <View style={{ width: "100%", height: "100%", alignItems: "center", justifyContent: "center", overflow: "hidden", backgroundColor: p.light ? "#e6e2da" : "#343332" }}>
    <If when={p.photo?.url && p.photo.url !== failed()} else={<Text style={{ color: p.light ? muted : "#c6c2bb", fontSize: 12 }}>{p.photo ? "照片不可用" : "Still"}</Text>}><Image src={p.photo?.url ?? ""} style={{ width: "100%", height: "100%", objectFit: p.fit ?? "cover" }} onError={() => failed.set(p.photo?.url ?? "")} /></If>
  </View>;
}
export function Switcher(p: { app: Library; prefix: string }) {
  return <View style={{ ...row, ...toolbarGlass, padding: 2, gap: 1 }}>
    <GlassButton label="相册墙" icon="grid" id={`${p.prefix}-wall`} segment darkInk selected={p.app.library().viewMode === "wall"} onPress={() => p.app.changeView("wall")} />
    <GlassButton label="唱片柜" icon="cabinet" id={`${p.prefix}-cabinet`} segment darkInk selected={p.app.library().viewMode === "cabinet"} onPress={() => p.app.changeView("cabinet")} />
  </View>;
}
const pill: ViewStyle = { height: 30, paddingHorizontal: 15, borderRadius: 15, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(246,246,245,0.92)" };
const wall: ViewStyle = { flex: 1, backgroundColor: "#e0dfdc", backgroundImage: "radial-gradient(circle at 50% 38%, rgba(255,255,255,0.86) 0%, rgba(255,255,255,0) 74%)" };
// A picture ledge seen from the front: what stands on it sits `sunk` behind its lip, so the lip is drawn over it.
const lip = 13, sunk = 5;
function LedgeLip(p: { bottom: number }) {
  return <View style={{ position: "absolute", left: 0, right: 0, bottom: p.bottom, height: lip, zIndex: 3, pointerEvents: "none", borderRadius: 2, backgroundColor: "#f4f3f0",
    backgroundImage: "linear-gradient(180deg, #ffffff 0%, #f8f7f5 16%, #e7e6e2 100%)", boxShadow: "0 1px 0 rgba(0,0,0,0.12), 0 4px 5px rgba(0,0,0,0.08), 0 18px 24px rgba(0,0,0,0.16)" }} />;
}
function albumMenu(app: Library, album: Album, inspect: () => void, at?: { x: number; y: number }) {
  return Menu.popup([
    { label: "打开相册", onSelect: () => app.openAlbum(album.id) },
    { label: "查看详情", onSelect: inspect }
  ], at);
}
async function frameOf(view: ViewRef | undefined, width: number, height: number, up = 0): Promise<Rect | undefined> {
  const m = await view?.measure();
  return m ? { x: m.pagePosition.x, y: m.pagePosition.y + up, width, height } : undefined;
}
/** The cover with the album's name, the same on the shelf and in the detail view. */
function Sleeve(p: { app: Library; album: Album; side: number; plain?: boolean }) {
  return <View style={{ width: "100%", height: "100%", overflow: "hidden", backgroundColor: "#343332" }}>
    <Artwork photo={p.app.cover(p.album)} />
    <View style={{ position: "absolute", bottom: 0, left: 0, right: 0, opacity: p.plain ? 0 : 1, transitionProperty: "opacity", transitionDuration: 200, paddingHorizontal: p.side * 0.06, paddingBottom: p.side * 0.055, paddingTop: p.side * 0.16, backgroundImage: "linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.62) 100%)" }}><Text style={{ color: "#fff", fontFamily: "Georgia", fontSize: p.side * 0.075, numberOfLines: 1 }}>{p.album.name}</Text></View>
  </View>;
}
/** `away` is where the cover's middle is from the middle of the shelves. */
function Cover(p: { app: Library; album: Album; index: number; side: number; away: { x: number; y: number }; stage: Stage }) {
  const entering = untracked(p.stage.entering) && !reduceMotion();
  const wait = Math.min(p.index, 9) * staggerMs;
  const lift = createAnimatedValue(entering ? -p.side * rise : 0), tilt = createAnimatedValue(entering ? 0 : recline);
  const rx = createAnimatedValue(0), ry = createAnimatedValue(0), shown = createAnimatedValue(entering ? 0 : 1), actions = createAnimatedValue(0);
  const up = signal(entering), over = signal(false), front = signal(false);
  let frame: ViewRef | undefined, leaning = 0, intro = 0;
  cleanup(() => { clearTimeout(leaning); clearTimeout(intro); });
  // Editions: a cover appears held above the shelf, then falls and leans back; each later cover waits longer for both.
  if (entering) {
    shown.timing(1, { duration: 16, easing: "linear", delay: introMs + wait });
    intro = setTimeout(fall, introMs + wait * 2);
  }
  function raise() {
    clearTimeout(leaning);
    up.set(true); front.set(true);
    if (reduceMotion()) return;
    lift.timing(-p.side * rise, { duration: liftMs, easing: outQuart });
    tilt.timing(0, { duration: liftMs, easing: outQuart });
  }
  function fall() {
    up.set(false);
    settle(rx, ry);
    if (reduceMotion()) { front.set(false); return; }
    lift.timing(0, { duration: dropMs, easing: inQuart });
    clearTimeout(leaning);
    leaning = setTimeout(() => tilt.timing(recline, { duration: dropMs, easing: inQuart }).then(end => { if (end.finished) front.set(false); }), dropMs * 0.6);
  }
  function enter() { if (p.stage.ready() && !p.stage.held() && !over()) { over.set(true); actions.timing(1, { duration: 200 }); raise(); } }
  function leave() { if (over()) { over.set(false); actions.set(0); fall(); } }
  function move(e: MouseEvent) { enter(); if (over()) lean(rx, ry, e.position, p.side, [4, 5.14]); }
  async function inspect() {
    if (!p.stage.ready() || p.stage.held()) return;
    const [raised, tilted] = await Promise.all([lift.getValue(), tilt.getValue()]);
    const from = await frameOf(frame, p.side, p.side, raised);
    if (!from) return;
    over.set(false); up.set(false);
    p.stage.inspect({ album: p.album, spine: false, from, tilt: tilted, landed,
      place: () => frameOf(frame, p.side, p.side, reduceMotion() ? 0 : -p.side * rise * 0.75) });
  }
  // The cover comes back held above the shelf, as it left, and falls again.
  function landed() {
    rx.set(0); ry.set(0);
    if (reduceMotion()) return;
    lift.set(-p.side * rise * 0.75); tilt.set(0); front.set(true);
    fall();
  }
  const hidden = () => p.stage.held() === p.album.id;
  // One camera faces the middle of the shelves, as in Editions, so covers to its sides lean towards it. The pointer
  // turns a cover about its middle; it leans back about the edge it stands on.
  const pose = (): TransformStep[] => [{ perspective: p.side * camera }, { translateX: p.away.x }, { translateY: p.away.y }, { rotateX: rx }, { rotateY: ry },
    { translateY: lift }, { translateY: p.side / 2 }, { rotateX: tilt }, { translateY: -p.side / 2 }, { translateX: -p.away.x }, { translateY: -p.away.y }];
  return <View ref={r => { frame = r; }} onMouseEnter={enter} onMouseMove={move} onMouseLeave={leave} onContextMenu={e => albumMenu(p.app, p.album, inspect, e.pagePosition)}
    style={{ width: p.side, height: p.side, zIndex: front() ? 2 : 1, opacity: hidden() ? 0 : 1, pointerEvents: hidden() ? "none" : "auto" }}>
    <View style={{ width: "100%", height: "100%", opacity: shown, transformOrigin: [p.side / 2 - p.away.x, p.side / 2 - p.away.y], transform: pose() }}>
      <Button testID={`album-${p.album.id}`} accessibilityLabel={`${p.album.name}，${p.album.photoIds.length} 张照片，查看相册详情`} onPress={inspect}
        style={{ width: "100%", height: "100%", boxShadow: up() ? "0 4px 6px rgba(0,0,0,0.08), 4px 26px 28px rgba(0,0,0,0.18)" : "0 2px 3px rgba(0,0,0,0.16), 3px 10px 16px rgba(0,0,0,0.20)", transitionProperty: "box-shadow", transitionDuration: up() ? liftMs : dropMs }}
        focusVisibleStyle={{ borderColor: "#81aff0", borderWidth: 2 }}>
        <Sleeve app={p.app} album={p.album} side={p.side} plain={over()} />
      </Button>
      <If when={over()}><View style={{ ...row, position: "absolute", left: 0, right: 0, bottom: p.side * 0.07, justifyContent: "center", opacity: actions, pointerEvents: "box-none" }}>
        <Button accessibilityLabel={`打开${p.album.name}`} style={pill} hoverStyle={{ backgroundColor: "#ffffff" }} onPress={() => p.app.openAlbum(p.album.id)}><Text style={{ color: ink, fontSize: 12 }}>打开</Text></Button>
        <Button accessibilityLabel={`${p.album.name}详情`} style={pill} hoverStyle={{ backgroundColor: "#ffffff" }} onPress={inspect}><Text style={{ color: ink, fontSize: 12 }}>详情</Text></Button>
      </View></If>
    </View>
  </View>;
}
function Wall(p: { app: Library; width: number; height: number; stage: Stage }) {
  const albums = () => p.app.library().albums;
  const span = () => Math.max(200, Math.min(1100, p.width - 100));
  const columns = () => Math.max(1, Math.min(albums().length, 5, Math.floor(span() / 185)));
  // Editions spaces covers 14% of their side apart, and shelves 27% of it.
  const side = () => Math.floor(Math.min(240, (span() - 64) / (columns() + (columns() - 1) * 0.14)));
  const pitch = () => side() * 1.27 + 12, foot = () => side() * 0.27 - 5;
  const shelves = computed(() => {
    const count = Math.ceil(albums().length / columns());
    return Array.from({ length: count }, (_, i) => albums().slice(i * columns(), (i + 1) * columns()).map((album, at, shelf) => ({
      album, index: i * columns() + at,
      away: { x: (at - (shelf.length - 1) / 2) * side() * 1.14, y: Math.max(-1, Math.min(1, i - (count - 1) / 2)) * pitch() },
    })));
  });
  const light = createAnimatedValue(untracked(p.stage.entering) && !reduceMotion() ? 0 : 1);
  light.timing(1, { duration: 1000, easing: "linear" });
  return <View style={wall}>
    <Scroll testID="gallery-wall" style={{ flex: 1, opacity: light }} contentStyle={{ alignItems: "center", paddingTop: Math.max(86, (p.height - shelves().length * pitch()) / 2), paddingBottom: 46 }}>
      <Each of={shelves()} key="index">{shelf => <View style={{ width: span(), height: pitch(), justifyContent: "flex-end", alignItems: "center" }}>
        <View style={{ flexDirection: "row", gap: side() * 0.14, marginBottom: foot() + lip - sunk }}>
          <Each of={shelf()} key={item => item.album.id}>{item => <Cover app={p.app} album={item().album} index={item().index} side={side()} away={item().away} stage={p.stage} />}</Each>
        </View>
        <LedgeLip bottom={foot()} />
      </View>}</Each>
    </Scroll>
  </View>;
}
const cjk = /[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff\uac00-\ud7af]/;
/** The album's name down its spine: upright characters for Chinese, Japanese and Korean, a line turned on its side otherwise. */
function SpineTitle(p: { name: string; width: number; height: number }) {
  const size = () => p.width * 0.4, room = () => p.height * 0.6, top = () => p.height * 0.055;
  const upright = () => { const all = [...p.name.replace(/\s+/g, "")], fit = Math.floor(room() / (size() * 1.2)); return all.length > fit ? [...all.slice(0, fit - 1), "︙"] : all; };
  return <If when={cjk.test(p.name)} else={<View style={{ position: "absolute", left: (p.width - room()) / 2, top: top() + (room() - p.width) / 2, width: room(), height: p.width, justifyContent: "center", rotate: "90deg" }}>
    <Text style={{ color: "#fff", fontFamily: "Georgia", fontSize: size(), numberOfLines: 1 }}>{p.name}</Text>
  </View>}>
    <View style={{ position: "absolute", left: 0, right: 0, top: top(), alignItems: "center" }}><Each of={upright()} key="index">{c => <Text style={{ color: "#fff", fontFamily: "Georgia", fontSize: size(), lineHeight: size() * 1.2 }}>{c()}</Text>}</Each></View>
  </If>;
}
/** An album seen from its spine, the same in the row and on the album turning out of it. */
function SpineFace(p: { app: Library; album: Album; width: number; height: number }) {
  return <View style={{ width: p.width, height: p.height, borderRadius: p.width * 0.06, overflow: "hidden", backgroundColor: "#343332" }}>
    <Artwork photo={p.app.cover(p.album)} />
    <View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, backgroundImage: "linear-gradient(90deg, rgba(255,255,255,0.26) 0%, rgba(255,255,255,0) 24%, rgba(0,0,0,0) 60%, rgba(0,0,0,0.30) 100%), linear-gradient(180deg, rgba(0,0,0,0.52) 0%, rgba(0,0,0,0.24) 36%, rgba(0,0,0,0) 62%)" }} />
    <SpineTitle name={p.album.name} width={p.width} height={p.height} />
  </View>;
}
function Spine(p: { app: Library; album: Album; stage: Stage }) {
  const over = signal(false), landing = signal(false);
  const lift = createAnimatedValue(0);
  let frame: ViewRef | undefined;
  const raised = () => over() && !p.stage.held(), up = () => raised() || landing();
  effect(() => { if (reduceMotion()) lift.set(0); else lift.spring(raised() ? -spine.lift : 0, spineSpring); });
  async function inspect() {
    if (p.stage.held()) return;
    const from = await frameOf(frame, spine.width, spine.height, await lift.getValue());
    if (!from) return;
    over.set(false);
    p.stage.inspect({ album: p.album, spine: true, from, tilt: 0, place: () => frameOf(frame, spine.width, spine.height, reduceMotion() ? 0 : -spine.lift),
      // The spine comes back above its place, still falling, and settles into the row.
      landed: () => { if (reduceMotion()) return; lift.set(-spine.lift); lift.spring(0, { ...spineSpring, velocity: spine.fall }); landing.set(true); setTimeout(() => landing.set(false), 250); } });
  }
  const hidden = () => p.stage.held() === p.album.id;
  return <View ref={r => { frame = r; }} onMouseEnter={() => over.set(true)} onMouseLeave={() => over.set(false)} onContextMenu={e => albumMenu(p.app, p.album, inspect, e.pagePosition)} style={{ zIndex: up() ? 1 : 0, opacity: hidden() ? 0 : 1 }}>
    <Button testID={`album-${p.album.id}`} accessibilityLabel={`${p.album.name}，${p.album.photoIds.length} 张照片，查看相册详情`} tooltip={<Hint label={p.album.name} />} onPress={inspect}
      style={{ width: spine.width, height: spine.height, borderRadius: 2, translate: [0, lift],
        boxShadow: up() ? "0 3px 4px rgba(0,0,0,0.14), 5px 14px 20px rgba(0,0,0,0.24)" : "0 1px 2px rgba(0,0,0,0.18), 3px 4px 8px rgba(0,0,0,0.16)", transitionProperty: "box-shadow", transitionDuration: 350, transitionTimingFunction: "ease-out" }}
      focusVisibleStyle={{ borderColor: "#81aff0", borderWidth: 2 }}>
      <SpineFace app={p.app} album={p.album} width={spine.width} height={spine.height} />
    </Button>
  </View>;
}
function Cabinet(p: { app: Library; width: number; height: number; stage: Stage }) {
  const span = () => Math.max(200, Math.min(1100, p.width - 100));
  const gap = 5, foot = 44, pitch = spine.height + spine.lift + lip - sunk + foot + 14;
  const shelves = computed(() => { const all = p.app.library().albums; const cap = Math.max(1, Math.floor((span() - 64 + gap) / (spine.width + gap))); return Array.from({length: Math.ceil(all.length / cap)}, (_, i) => all.slice(i * cap, (i + 1) * cap)); });
  return <View style={wall}>
    <Scroll testID="gallery-cabinet" style={{ flex: 1 }} contentStyle={{ alignItems: "center", paddingTop: Math.max(60, (p.height - shelves().length * pitch) / 2), paddingBottom: 30 }}>
      <Each of={shelves()} key="index">{shelf => <View style={{ width: span(), height: pitch, justifyContent: "flex-end", alignItems: "center" }}>
        <View style={{ flexDirection: "row", alignItems: "flex-end", gap, marginBottom: foot + lip - sunk }}>
          <Each of={shelf()} key={a => a.id}>{a => <Spine app={p.app} album={a()} stage={p.stage} />}</Each>
        </View>
        <LedgeLip bottom={foot} />
      </View>}</Each>
    </Scroll>
  </View>;
}
/** The album taken to the middle of the window over a blurred gallery, as Editions shows an album's details. */
function Detail(p: { app: Library; flight: Flight; width: number; height: number; origin: { x: number; y: number }; close: () => void }) {
  const f = p.flight;
  const side = () => Math.round(Math.min(f.spine ? 430 : f.from.width * closeUp, p.height * 0.55, p.width * 0.46));
  const left = () => (p.width - side()) / 2, top = () => (p.height - side()) / 2 - 18;
  const depth = () => side() * thickness, eye = () => side() * camera / closeUp;
  // In the row the album stands a quarter turn away: its spine is half a cover nearer the eye than its cover will be,
  // so it shows `near` times larger, and lies to the left of the line the album turns about.
  const near = eye() / (eye() - side() / 2);
  // Where the album shows `rect`, as an offset and a scale from its place in the middle.
  const pose = (rect: Rect) => ({ x: rect.x - p.origin.x + (f.spine ? rect.width : rect.width / 2) - left() - side() / 2, y: rect.y - p.origin.y + rect.height / 2 - top() - side() / 2, scale: rect.height / side() / (f.spine ? near : 1) });
  const start = pose(f.from);
  const x = createAnimatedValue(start.x), y = createAnimatedValue(start.y), scale = createAnimatedValue(start.scale), turn = createAnimatedValue(f.spine ? 90 : 0), tilt = createAnimatedValue(f.tilt);
  const rx = createAnimatedValue(0), ry = createAnimatedValue(0), veil = createAnimatedValue(0), words = createAnimatedValue(0), action = createAnimatedValue(0), edges = createAnimatedValue(f.spine ? 1 : 0);
  const active = signal(false);
  let leaving = false;
  const calm = reduceMotion(), ms = f.spine ? takeMs : pullMs;
  const arrived = (end: { finished: boolean }) => { if (end.finished && !leaving) { active.set(true); edges.timing(1, { duration: calm ? 0 : 200 }); } };
  if (f.spine) {
    carry(x, start.x, 0); hop(y, start.y, start.y - f.from.height * out, 0); carry(turn, 90, 0);
    carry(scale, start.scale, 1).then(arrived);
  } else {
    pull(x, start.x, 0); pull(y, start.y, 0);
    pull(scale, start.scale, 1).then(arrived);
  }
  if (calm) tilt.set(0); else tilt.timing(0, { duration: liftMs, easing: outQuart });
  veil.timing(1, { duration: calm ? 0 : ms * 0.7, easing: "easeOut" });
  words.timing(1, { duration: calm ? 0 : 300, delay: calm ? 0 : ms - 380 });
  action.timing(1, { duration: calm ? 0 : 180, delay: calm ? 0 : ms - 100 });
  async function dismiss() {
    if (leaving) return;
    leaving = true; active.set(false);
    settle(rx, ry);
    words.timing(0, { duration: 160 }); action.timing(0, { duration: 120 });
    veil.timing(0, { duration: calm ? 0 : ms, easing: "easeIn" });
    const [place, across, down, scaled, turned] = await Promise.all([f.place(), x.getValue(), y.getValue(), scale.getValue(), turn.getValue()]);
    const home = pose(place ?? f.from);
    if (f.spine) {
      carry(x, across, home.x, true); hop(y, down, home.y - f.from.height * out, home.y, true); carry(turn, turned, 90, true);
      await carry(scale, scaled, home.scale, true);
    } else {
      edges.timing(0, { duration: 120 });
      pull(x, across, home.x); pull(y, down, home.y);
      await pull(scale, scaled, home.scale);
    }
    p.close(); f.landed();
  }
  effect(() => { if (!p.app.library().albums.some(a => a.id === f.album.id)) p.close(); });
  cleanup(keymap.bind("escape", dismiss));
  // The album is a box behind its cover. Each face is a view turned onto its side of the box, under the cover: a face
  // turned away from the eye lies within the cover's outline, a face turned to it beside the cover.
  const body: TransformStep[] = [{ translateX: x }, { translateY: y }, { scale }, { perspective: eye() }, { rotateX: rx }, { rotateY: ry }, { rotateY: turn }, { rotateX: tilt }];
  const face = (width: number, height: number, onto: TransformStep[]): ViewStyle => ({ position: "absolute", left: (side() - width) / 2, top: (side() - height) / 2, width, height, backfaceVisibility: "hidden", transform: [...body, ...onto] });
  const back: TransformStep[] = [{ translateX: -side() / 2 }, { rotateY: -90 }, { translateX: -depth() / 2 }];
  const paper = (across: boolean): ViewStyle => ({ opacity: edges, backgroundColor: "#dedad1", backgroundImage: `linear-gradient(${across ? 90 : 180}deg, rgba(0,0,0,0.10) 0%, rgba(0,0,0,0) 30%, rgba(0,0,0,0) 70%, rgba(0,0,0,0.12) 100%)` });
  return <View testID="album-detail" style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, zIndex: 5 }}>
    <View testID="detail-backdrop" accessibilityLabel="放回相册" onPress={dismiss} style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, opacity: veil, backdropFilter: "blur(7px)", maskImage: "linear-gradient(#000, #000)", backgroundColor: "rgba(226,226,225,0.3)" }} />
    <View style={{ position: "absolute", left: 34, top: 0, bottom: 36, width: Math.max(120, left() - 60), justifyContent: "center", gap: 10, opacity: words, pointerEvents: "none" }}>
      <Text style={{ color: ink, fontSize: p.width < 900 ? 24 : 30, fontFamily: "Georgia", numberOfLines: 3 }}>{f.album.name}</Text>
      <Text style={{ color: muted, fontSize: 13 }}>{`${f.album.photoIds.length} 张照片`}</Text>
    </View>
    {/* Clipping flattens the turning album into this layer: left in the backdrop's space, its far half sinks behind the blur. */}
    <View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, overflow: "hidden", pointerEvents: "box-none" }}>
      <View onMouseMove={e => { if (active()) lean(rx, ry, e.position, side(), [6.67, 8.57], 0.2); }} onMouseLeave={() => settle(rx, ry)} style={{ position: "absolute", left: left(), top: top(), width: side(), height: side() }}>
        <If when={f.spine}><View style={{ ...face(depth(), side(), back), opacity: turn.interpolate({ inputRange: [0, 90], outputRange: [0, 1] }), boxShadow: "0 14px 30px rgba(0,0,0,0.30)" }} /></If>
        <View style={{ ...face(side(), side(), []), boxShadow: "0 24px 48px rgba(0,0,0,0.25)" }} />
        <View style={{ ...face(depth(), side(), [{ translateX: side() / 2 }, { rotateY: 90 }, { translateX: depth() / 2 }]), ...paper(true) }} />
        <View style={{ ...face(side(), depth(), [{ translateY: -side() / 2 }, { rotateX: 90 }, { translateY: -depth() / 2 }]), ...paper(false) }} />
        <View style={{ ...face(side(), depth(), [{ translateY: side() / 2 }, { rotateX: -90 }, { translateY: depth() / 2 }]), ...paper(false) }} />
        <View style={{ ...face(depth(), side(), back), opacity: edges }}><SpineFace app={p.app} album={f.album} width={depth()} height={side()} /></View>
        <View style={face(side(), side(), [])}><Sleeve app={p.app} album={f.album} side={side()} /></View>
      </View>
    </View>
    <View style={{ position: "absolute", left: 0, right: 0, top: top() + side() + 22, alignItems: "center", opacity: action, pointerEvents: "box-none" }}>
      <Button testID="detail-open" accessibilityLabel="打开相册" onPress={() => p.app.openAlbum(f.album.id)} style={{ ...pill, height: 38, borderRadius: 19, paddingHorizontal: 22, backgroundColor: "#1f1e1c" }} hoverStyle={{ backgroundColor: "#3a3835" }} focusVisibleStyle={{ borderWidth: 2, borderColor: "#87b5f4" }}><Text style={{ color: "#fff", fontSize: 13 }}>打开相册</Text></Button>
    </View>
    <View style={{ position: "absolute", top: 6, right: 10 }}><GlassButton darkInk icon="close" id="detail-close" label="放回" onPress={dismiss} /></View>
  </View>;
}
export function Gallery(p: { app: Library }) {
  const size = signal({ width: 920, height: 680 }), origin = signal({ x: 0, y: 0 });
  const flight = signal<Flight | undefined>(undefined);
  // The shelf's entrance plays once per visit to the gallery, and nothing answers the pointer until it ends.
  const entering = signal(!reduceMotion()), ready = signal(reduceMotion());
  const albums = untracked(() => p.app.library().albums.length);
  const introEnd = setTimeout(() => { entering.set(false); ready.set(true); }, untracked(() => p.app.library().viewMode) === "wall" && albums ? introMs + Math.min(albums - 1, 9) * staggerMs * 2 + dropMs * 1.6 : 0);
  cleanup(() => clearTimeout(introEnd));
  let root: ViewRef | undefined;
  const stage: Stage = { entering, ready, held: () => flight()?.album.id ?? "", inspect: async next => {
    if (flight()) return;
    const m = await root?.measure();
    if (m) origin.set(m.pagePosition);
    flight.set(next);
  } };
  return <View ref={r => { root = r; }} style={{ flex: 1, backgroundColor: "#f8f8f7" }} onLayout={e => size.set({ width: Math.max(200, e.bounds.size.width), height: Math.max(200, e.bounds.size.height) })}>
    <If when={p.app.library().albums.length > 0} else={<View style={centered}><Text style={{ color: ink, fontSize: 24, fontFamily: "Georgia" }}>创建第一本相册</Text><Text style={{ color: muted, fontSize: 14 }}>把照片和旁边的故事收在一起。</Text><Action label="新建相册" onPress={() => p.app.panel.set("create")} /></View>}>
      <If when={p.app.library().viewMode === "wall"} else={<Cabinet app={p.app} width={size().width} height={size().height} stage={stage} />}><Wall app={p.app} width={size().width} height={size().height} stage={stage} /></If>
    </If>
    <View style={{ ...row, position: "absolute", top: 6, left: 10, right: 10, justifyContent: "space-between", pointerEvents: "box-none" }}>
      <View desktop={{ windowDrag: true }} style={{ flex: 1, height: 34, justifyContent: "center" }}>
        <Text style={{ marginLeft: platform.os === "macos" ? 70 : 8, fontSize: 19, fontWeight: "700", fontFamily: "Georgia", color: ink }}>Still</Text>
      </View>
      <Switcher app={p.app} prefix="home" />
      <View style={{ ...row, flex: 1, justifyContent: "flex-end", pointerEvents: "box-none" }}><GlassButton darkInk icon="plus" id="home-add" label="添加相册" onPress={() => p.app.panel.set("create")} /></View>
    </View>
    <If when={flight()}><Detail app={p.app} flight={flight()!} width={size().width} height={size().height} origin={origin()} close={() => flight.set(undefined)} /></If>
  </View>;
}
