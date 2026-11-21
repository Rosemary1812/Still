import { open, test } from "nsh/test";

test("closing the display pauses the player and resuming reopens the movie", async () => {
  const app = await open("./native/tests/DisplayHarness.tsx", { platform: "macos" });
  await app.press("id:start");
  await app.waitFor("Playing");
  await app.window("display").pressClose();
  await app.waitFor("Paused");
  await app.press("id:resume");
  await app.waitUntil(() => app.windowIds().includes("display"));
  await app.waitFor("Playing");
  await app.waitFor("Paused", { timeout: 15000 });
});

test("video controls keep album shortcuts while note fields keep cursor keys", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  await app.press("id:home-add");
  await app.type("id:album-name", "视频翻阅测试");
  await app.press("id:save-album");
  const files = [
    "./native/tests/fixtures/first.png",
    "../toolchain/nsh/crates/nsh-platform-macos/tests/host/clip.mp4",
  ].map(path => new URL(path, import.meta.url).href.replace(/^asset:/, "file://"));
  await app.dropFiles("id:album-empty", files);
  await app.waitFor("id:photo-wall");
  await app.press("id:album-read");
  await app.keyboard.press("right");
  await app.press("id:media-play");
  await app.waitFor("id:media-player");
  await app.keyboard.press("left");
  await app.waitFor("01 / 2");
  await app.keyboard.press("right");
  await app.type("id:reader-title", "视频标题");
  await app.keyboard.press("left");
  await app.waitFor("02 / 2");
  await app.keyboard.press("escape");
  await app.keyboard.press("left");
  await app.waitFor("01 / 2");
  await app.keyboard.press("right");
  await app.press("id:media-play");
  await app.waitFor("id:media-player");
  await app.keyboard.press("escape");
  await app.waitFor("id:photo-wall");
});
