import { cleanup, effect, Image, mount, platform, signal, Text, View } from "nsh";
import { Button } from "nsh/base";
import { currentWindow, Tray, Window } from "nsh/desktop";
import { Photos } from "contactsheet/native";
import first from "./assets/sample-1.png";
import second from "./assets/sample-2.png";
import third from "./assets/sample-3.png";
import icon from "./assets/tray.svg";

const state = signal(Photos.snapshot());
const error = signal("");
const busy = signal(false);
function refresh() { state.set(Photos.snapshot()); }
function samples() { Photos.samples([first.url, second.url, third.url]); refresh(); }
function next() { Photos.next(); refresh(); }
function previous() { Photos.previous(); refresh(); }
function toggle() { Photos.toggle(); refresh(); }
async function choose() {
  if (busy()) return;
  busy.set(true); error.set("");
  try { await Photos.choose(); refresh(); }
  catch (cause) { error.set(String(cause)); }
  finally { busy.set(false); }
}
async function applePhoto() {
  if (busy()) return;
  busy.set(true); error.set("");
  try { await Photos.applePhoto(); refresh(); }
  catch (cause) { error.set(String(cause)); }
  finally { busy.set(false); }
}
function Action(props: { label: string; onPress: () => void; disabled?: boolean; id?: string }) {
  return <Button testID={props.id} onPress={props.onPress} disabled={props.disabled} class="rounded-lg bg-slate-700 px-4 py-3 active:bg-slate-600 disabled:opacity-40"><Text class="text-sm text-white">{props.label}</Text></Button>;
}
function Controls(props: { prefix: string }) {
  return <View class="flex-row gap-3 justify-center">
    <Action id={`${props.prefix}-previous`} label="Previous" onPress={previous} />
    <Action id={`${props.prefix}-toggle`} label={state().playing ? "Pause" : "Play"} onPress={toggle} disabled={state().paths.length === 0} />
    <Action id={`${props.prefix}-next`} label="Next" onPress={next} />
  </View>;
}
function Picture() {
  return <View class="flex-1 rounded-xl overflow-hidden bg-slate-900 items-center justify-center">
    <If when={state().current} else={<Text class="text-slate-400">Choose images or load the sample set.</Text>}>
      <Image src={state().current ?? ""} style={{ width: "100%", height: "100%", objectFit: "contain" }} onError={(event) => error.set(event.message)} />
    </If>
  </View>;
}
function Display() {
  return <View class="flex-1 bg-slate-950 p-5 gap-4">
    <Picture />
    <Text class="text-slate-300 text-center">{`Photo ${state().current ? state().paths.indexOf(state().current ?? "") + 1 : 0} / ${state().paths.length}`}</Text>
    <Controls prefix="display" />
  </View>;
}
function showDisplay() {
  Window.open(Display, { id: "display", title: "Contact Sheet · Display", defaultSize: { width: 620, height: 520 } }).focus();
}
function App() {
  const main = currentWindow();
  main.on("closePress", () => main.hide());
  const poll = setInterval(() => {
    const snapshot = Photos.snapshot();
    if (snapshot.revision !== state().revision) state.set(snapshot);
  }, 200);
  cleanup(() => clearInterval(poll));
  effect(() => Tray.set({ icon, tooltip: state().playing ? "Contact Sheet · Playing" : "Contact Sheet · Paused", onClick: () => main.focus(), menu: [
    { label: "Show library", onSelect: () => main.focus() },
    { label: "Show display", onSelect: showDisplay },
    { label: state().playing ? "Pause" : "Play", onSelect: toggle },
    { label: "Next", onSelect: next },
    { type: "separator" }, { role: "quit" },
  ] }));
  cleanup(() => Tray.set(null));
  return <View class="flex-1 bg-slate-950 p-6 gap-4">
    <View class="flex-row justify-between items-center">
      <View class="gap-1"><Text class="text-2xl font-semibold text-white">Contact Sheet</Text><Text class="text-slate-400">{`NSH prototype · ${platform.os} · one Rust player`}</Text></View>
      <Action label="Open display" onPress={showDisplay} />
    </View>
    <View class="flex-row gap-3"><Action label={busy() ? "Choosing…" : "Choose images"} onPress={choose} disabled={busy()} /><Action label="Load samples" onPress={samples} /><If when={platform.os === "macos"}><Action label="Load latest Apple photo" onPress={applePhoto} disabled={busy()} /></If></View>
    <Picture />
    <Text class="text-center text-slate-300">{`${state().paths.length} images · ${state().playing ? "Playing" : "Paused"} · 5 seconds per image`}</Text>
    <Controls prefix="library" />
    <If when={error()}><Text class="text-red-300">{error()}</Text></If>
    <Text class="text-xs text-slate-500">Closing this window keeps playback running. Use the tray menu to reopen or quit.</Text>
  </View>;
}
mount(App);
