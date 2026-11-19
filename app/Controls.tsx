import { Canvas, Path2D, Text, View, type ViewStyle } from "nsh";
import { Button, Input, Tooltip } from "nsh/base";

export const ink = "#262421";
export const muted = "#68635d";
export const paper = "#f6f5f2";
export const glass: ViewStyle = {
  glassEffect: "regular", glassTintColor: "rgba(35,33,31,0.32)", backdropFilter: "blur(18px)",
  backgroundColor: "rgba(38,37,36,0.36)", borderColor: "rgba(255,255,255,0.45)", borderWidth: 1,
  boxShadow: "0 3px 8px rgba(0,0,0,0.19)", borderRadius: 24,
};
export const row: ViewStyle = { flexDirection: "row", alignItems: "center", gap: 8 };
export const centered: ViewStyle = { flex: 1, alignItems: "center", justifyContent: "center", gap: 14 };
const lines = {
  plus: ["M12 5v14", "M5 12h14"],
  settings: ["M9.3 3.5l.7-2h4l.7 2 2.2 1.3 2.2-.4 2 3.5-1.4 1.7v2.7l1.4 1.7-2 3.5-2.2-.4-2.2 1.3-.7 2h-4l-.7-2-2.2-1.3-2.2.4-2-3.5 1.4-1.7V9.6L2.9 7.9l2-3.5 2.2.4z", "M15.4 11a3.4 3.4 0 1 1-6.8 0 3.4 3.4 0 0 1 6.8 0z"],
  cabinet: ["M5 8h14", "M7 5h10", "M9 2.5h6"],
  close: ["M6 6l12 12", "M18 6L6 18"],
  grid: [],
} as const;
type Symbol = keyof typeof lines;
const paths = { plus: lines.plus.map(p => new Path2D(p)), settings: lines.settings.map(p => new Path2D(p)), cabinet: lines.cabinet.map(p => new Path2D(p)), close: lines.close.map(p => new Path2D(p)), grid: [] };
function Glyph(p: { name: Symbol; darkInk: boolean }) {
  return <Canvas style={{ width: 16, height: 16, pointerEvents: "none" }} draw={(cx, {width}) => {
    cx.scale(width / 24, width / 24); cx.strokeStyle = p.darkInk ? "#393733" : "#ffffff"; cx.fillStyle = cx.strokeStyle; cx.lineWidth = 1.8; cx.lineCap = "round"; cx.lineJoin = "round";
    if (p.name === "grid") { for (let y = 0; y < 3; y++) for (let x = 0; x < 3; x++) cx.fillRect(2 + x * 7, 2 + y * 7, 5.3, 5.3); }
    else { for (const path of paths[p.name]) cx.stroke(path); }
    if (p.name === "cabinet") { cx.beginPath(); cx.roundRect(2, 10, 20, 12, 3); cx.fill(); }
  }} />;
}
export function Hint(p: { label: string }) {
  return <Tooltip placement="bottom" style={{ backgroundColor: "#343331", borderRadius: 6, paddingHorizontal: 8, paddingVertical: 4 }}><Text style={{ color: "#fff", fontSize: 12 }}>{p.label}</Text></Tooltip>;
}
// Let the native lens sample the artwork directly. A painted fill here flattens the lens.
export const toolbarGlass: ViewStyle = {
  glassEffect: "clear", backdropFilter: "blur(6px)",
  glassTintColor: "rgba(40, 35, 34, 0.16)", borderRadius: 20,
  borderWidth: 0.5, borderColor: "rgba(255,255,255,0.52)",
  boxShadow: "0 1px 3px rgba(0,0,0,0.16)",
};
export function GlassButton(p: { id: string; label: string; icon: Symbol; onPress: () => void; segment?: boolean; selected?: boolean; darkInk?: boolean }) {
  return <Button testID={p.id} accessibilityLabel={p.label} selected={p.selected} onPress={p.onPress} tooltip={<Hint label={p.label} />}
    style={{
      ...(p.segment ? {} : toolbarGlass),
      width: 34, height: p.segment ? 30 : 34, borderRadius: 17,
      alignItems: "center", justifyContent: "center",
      backgroundColor: p.segment && p.selected ? "rgba(255,255,255,0.23)" : "transparent",
    }}
    hoverStyle={{ backgroundColor: "rgba(180,176,172,0.16)" }}
    activeStyle={{ opacity: 0.75 }}
    focusVisibleStyle={{ borderColor: "#87b5f4", borderWidth: 2 }}>
    <Glyph name={p.icon} darkInk={p.darkInk ?? false} />
  </Button>;
}
export function Action(p: { label: string; onPress: () => void; id?: string; disabled?: boolean; primary?: boolean; danger?: boolean }) {
  return <Button testID={p.id} accessibilityLabel={p.label} disabled={p.disabled} onPress={p.onPress} style={{ paddingVertical: 7, paddingHorizontal: 12, backgroundColor: p.primary ? "#363430" : "#eceae5", borderRadius: 9, alignItems: "center", justifyContent: "center" }} hoverStyle={{ opacity: 0.82 }} disabledStyle={{ opacity: 0.4 }} focusVisibleStyle={{ borderWidth: 1, borderColor: "#698fc0" }}><Text style={{ color: p.primary ? "#fff" : p.danger ? "#963a39" : ink, fontSize: 13 }}>{p.label}</Text></Button>;
}
export function Field(p: { label: string; value: string; change: (s: string) => void; id: string; multiline?: boolean; placeholder?: string }) {
  return <View style={{ gap: 5 }}><Text style={{ color: muted, fontSize: 12 }}>{p.label}</Text><Input testID={p.id} placeholder={p.placeholder ?? p.label} value={p.value} onChange={e => p.change(e.value)} multiline={p.multiline} style={{ height: p.multiline ? 78 : 35, color: ink, fontSize: 14, paddingHorizontal: 9, borderRadius: 6, borderWidth: 1, borderColor: "#cbc8bf", backgroundColor: "#fff" }} /></View>;
}
