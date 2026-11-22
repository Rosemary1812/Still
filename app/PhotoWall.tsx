import { itemLabel, mediaName } from "./MediaLabels";
import { cleanup, computed, PanResponder, signal, View } from "nsh";
import { Button } from "nsh/base";
import { Artwork } from "./Gallery";
import type { Library, Photo } from "./DesktopState";

// Four rows drift past at their own offsets, so the album reads as a wall and not a grid.
export function PhotoWall(p: { app: Library; width: number; height: number; paused: boolean; menu: (photo: Photo, at: { x: number; y: number }) => void }) {
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
  const index = (r: number, x: number) => {
    const n = p.app.photos().length;
    if (r >= n) return r % n;
    const period = Math.ceil((n - r) / 4);
    return r + 4 * (((x + whole[r]()) % period + period) % period);
  };
  const at = (r: number, x: number) => p.app.photos()[index(r, x)];
  return <View testID="photo-wall" style={{ flex: 1, overflow: "hidden" }} {...drag.panHandlers}>
    <Each of={[0, 1, 2, 3]}>{r => <View style={{ flexDirection: "row", height: edge(), flexShrink: 0, transform: [{ translateX: -(position(r()) - Math.floor(position(r()))) * edge() }] }}>
      <Each of={cells()}>{x => <View style={{ height: edge(), width: edge(), flexShrink: 0 }} onContextMenu={e => { const photo = at(r(), x()); if (photo) p.menu(photo, e.pagePosition); }}>
        <Button accessibilityLabel={itemLabel(at(r(), x()), `查看${mediaName(at(r(), x()))} ${1 + index(r(), x())}`)} onPress={() => { const photo = at(r(), x()); if (photo) p.app.select(photo.id); }}
          style={{ flex: 1 }} hoverStyle={{ opacity: 0.86 }} focusVisibleStyle={{ borderColor: "#9cc4fb", borderWidth: 3 }}>
          <Artwork photo={at(r(), x())} compactBadge={edge() < 96} />
        </Button>
      </View>}</Each>
    </View>}</Each>
  </View>;
}
