import { open, test } from "nsh/test";
const png = (variant: number) => new Uint8Array(variant ? [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 120, 184, 34, 20, 0, 4, 76, 1, 223, 246, 191, 20, 245, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130] : [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 208, 13, 74, 4, 0, 1, 144, 0, 225, 231, 109, 252, 87, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);
test("seed an isolated library for the native keyboard regression", async () => {
 const app = await open("./App.tsx", { platform: "macos" });
 app.onPick(() => [{name:"a.png",data:png(0)},{name:"b.png",data:png(1)}]);
 await app.press("id:home-add"); await app.type("id:album-name", "宿主验收"); await app.press("id:save-album"); await app.press("id:empty-files"); await app.waitFor("id:photo-wall");
});
