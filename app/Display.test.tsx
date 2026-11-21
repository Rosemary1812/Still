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
