import { open, test } from "nsh/test";
test("seed an isolated library for the native keyboard regression", async () => {
 const app = await open("./App.tsx", { platform: "macos" });
 await app.press("id:home-add"); await app.type("id:album-name", "宿主验收"); await app.press("id:save-album"); await app.dropFiles("id:album-empty", [new URL("./native/tests/fixtures", import.meta.url).href.replace(/^asset:/, "file://")]); await app.waitFor("id:photo-wall");
});
