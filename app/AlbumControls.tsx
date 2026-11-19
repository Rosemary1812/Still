import { Canvas, Path2D, Text, View, type ViewRef, type ViewStyle } from "nsh";
import { Button } from "nsh/base";
import { Hint } from "./Controls";

// Inside an album every control sits on photographs, so one ink serves both pages.
export const onPhoto = "#ffffff";
export const onPhotoMuted = "rgba(255,255,255,0.62)";
export const onPhotoFaint = "rgba(255,255,255,0.36)";
export const stage = "#161514";
export const serif = "Georgia";

export const pill: ViewStyle = {
  glassEffect: "regular", glassTintColor: "rgba(30,28,27,0.34)", backdropFilter: "blur(18px)",
  backgroundColor: "rgba(34,32,31,0.42)", borderColor: "rgba(255,255,255,0.22)", borderWidth: 0.5,
  boxShadow: "0 2px 10px rgba(0,0,0,0.22)", borderRadius: 18,
};
export const fade: ViewStyle = { transitionProperty: "opacity", transitionDuration: 260, transitionTimingFunction: "ease-in-out" };

const strokes = {
  back: ["M14.5 5.5L8 12l6.5 6.5"],
  previous: ["M14.5 5.5L8 12l6.5 6.5"],
  next: ["M9.5 5.5L16 12l-6.5 6.5"],
  plus: ["M12 5.5v13", "M5.5 12h13"],
  wall: ["M4 4.5h6.5V11H4z", "M13.5 4.5H20V11h-6.5z", "M4 13.5h6.5V20H4z", "M13.5 13.5H20V20h-6.5z"],
  reader: ["M3.5 5.5h10v13h-10z", "M16.5 8.5h4", "M16.5 12h4", "M16.5 15.5h2.5"],
  more: [],
  play: [],
  close: ["M6.5 6.5l11 11", "M17.5 6.5l-11 11"],
} as const;
export type IconName = keyof typeof strokes;
const paths = Object.fromEntries(Object.entries(strokes).map(([name, list]) => [name, list.map(d => new Path2D(d))])) as Record<IconName, Path2D[]>;
const playShape = new Path2D("M8.5 5.6v12.8a.6.6 0 0 0 .9.5l10.3-6.4a.6.6 0 0 0 0-1L9.4 5.1a.6.6 0 0 0-.9.5z");

export function Icon(p: { name: IconName; size?: number; color?: string }) {
  return <Canvas style={{ width: p.size ?? 16, height: p.size ?? 16, pointerEvents: "none" }} draw={(cx, { width }) => {
    cx.scale(width / 24, width / 24);
    cx.strokeStyle = p.color ?? onPhoto; cx.fillStyle = cx.strokeStyle;
    cx.lineWidth = 1.9; cx.lineCap = "round"; cx.lineJoin = "round";
    if (p.name === "more") { for (const x of [5, 12, 19]) { cx.beginPath(); cx.arc(x, 12, 1.75, 0, Math.PI * 2); cx.fill(); } }
    else if (p.name === "play") cx.fill(playShape);
    else for (const path of paths[p.name]) cx.stroke(path);
  }} />;
}

// Where a menu opens for the button that asked: under its left edge, as a toolbar's menus do.
export type Anchor = () => Promise<{ x: number; y: number } | undefined>;
export function IconButton(p: { id: string; label: string; icon: IconName; onPress: (anchor: Anchor) => void; selected?: boolean; disabled?: boolean; size?: number }) {
  const size = p.size ?? 30;
  let frame: ViewRef | undefined;
  const anchor: Anchor = async () => {
    const at = await frame?.measure();
    return at ? { x: at.pagePosition.x, y: at.pagePosition.y + size + 8 } : undefined;
  };
  return <View ref={r => (frame = r)}><Button testID={p.id} accessibilityLabel={p.label} selected={p.selected} disabled={p.disabled} tooltip={<Hint label={p.label} />} onPress={() => p.onPress(anchor)}
    style={{ width: size + 4, height: size, borderRadius: size / 2, alignItems: "center", justifyContent: "center", backgroundColor: p.selected ? "rgba(255,255,255,0.24)" : "transparent" }}
    hoverStyle={{ backgroundColor: p.selected ? "rgba(255,255,255,0.28)" : "rgba(255,255,255,0.13)" }}
    activeStyle={{ opacity: 0.7 }} disabledStyle={{ opacity: 0.35 }}
    focusVisibleStyle={{ borderColor: "#9cc4fb", borderWidth: 2 }}>
    <Icon name={p.icon} />
  </Button></View>;
}

export function Quiet(p: { id?: string; label: string; onPress: () => void; disabled?: boolean; danger?: boolean; filled?: boolean }) {
  return <Button testID={p.id} accessibilityLabel={p.label} disabled={p.disabled} onPress={p.onPress}
    style={{ paddingVertical: 6, paddingHorizontal: 12, borderRadius: 14, backgroundColor: p.filled ? "rgba(255,255,255,0.92)" : "rgba(255,255,255,0.10)", alignItems: "center", justifyContent: "center" }}
    hoverStyle={{ backgroundColor: p.filled ? "#ffffff" : "rgba(255,255,255,0.18)" }} activeStyle={{ opacity: 0.7 }} disabledStyle={{ opacity: 0.45 }}
    focusVisibleStyle={{ borderColor: "#9cc4fb", borderWidth: 2 }}>
    <Text style={{ color: p.filled ? "#1d1c1a" : p.danger ? "#ff9d94" : onPhoto, fontSize: 12.5 }}>{p.label}</Text>
  </Button>;
}

export function Divider() {
  return <View style={{ width: 0.5, height: 16, marginHorizontal: 3, backgroundColor: "rgba(255,255,255,0.24)" }} />;
}
