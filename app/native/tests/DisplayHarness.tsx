import { mount, signal, Text, View } from "nsh";
import { Button } from "nsh/base";
import { Photos } from "contactsheet/native";
import { makeLibrary } from "../../DesktopState";
import { openDisplay, toggleDisplay } from "../../Desktop";

function DisplayHarness() {
  const app = makeLibrary();
  const error = signal("");
  async function start() {
    try {
      const id = Photos.createAlbum("放映窗口测试");
      const clip = new URL("../../../toolchain/nsh/crates/nsh-platform-macos/tests/host/clip.mp4", import.meta.url);
      await Photos.addDropped(id, [clip.href.replace(/^asset:/, "file://")]);
      app.refresh();
      openDisplay(app, id);
    } catch (cause) { error.set(String(cause)); }
  }
  return <View style={{ flex: 1 }}>
    <Button testID="start" onPress={() => void start()}><Text>Start</Text></Button>
    <Button testID="resume" onPress={() => toggleDisplay(app)}><Text>Resume</Text></Button>
    <Text>{app.player().playing ? "Playing" : "Paused"}</Text>
    <Text>{error()}</Text>
  </View>;
}

mount(DisplayHarness);
