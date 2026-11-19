import { expect, open, test } from "nsh/test";

// The desktop runner supplies an isolated STILL_LIBRARY_DIR. Two valid tiny PNGs
// exercise the actual native importer and deduplication without a system picker.
const png = (variant: number) => new Uint8Array(variant ? [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 120, 184, 34, 20, 0, 4, 76, 1, 223, 246, 191, 20, 245, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130] : [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 208, 13, 74, 4, 0, 1, 144, 0, 225, 231, 109, 252, 87, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

test("create an album, switch both gallery controls, read, annotate and present", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  app.onPick(() => [{ name: "first.png", data: png(0) }, { name: "second.png", data: png(1) }]);
  // An album leaves its place for the detail view and goes back, in either gallery.
  async function pullOut() {
    await app.press("旅行相册，2 张照片，查看相册详情");
    await app.waitFor("id:detail-open");
    await app.press("id:detail-close");
    await app.waitUntil(() => !app.shows("id:album-detail"));
  }
  await app.press("id:home-add");
  await app.type("id:album-name", "旅行相册");
  await app.press("id:save-album");
  await app.press("从文件选择");
  await app.waitFor("id:photo-wall");
  await app.press("翻阅");
  await app.waitFor("1 / 2");
  await app.keyboard.press("right");
  await app.waitFor("2 / 2");
  await app.press("编辑描述");
  await app.type("id:note-title", "湖边的早晨");
  await app.press("保存描述");
  await app.waitFor("湖边的早晨");
  await app.press("设为相册封面");
  await app.waitFor("当前相册封面");
  await app.press("放映");
  await app.waitFor("id:display-next");
  await app.press("id:display-next");
  await app.waitFor("湖边的早晨");
  await app.press("id:display-edit");
  await app.type("id:note-location", "杭州");
  await app.press("保存描述");
  await app.waitFor("杭州");
  await app.window("display").pressClose();
  await app.press("‹ 全部相册");
  await app.press("id:home-wall");
  await app.waitFor("id:gallery-wall");
  await pullOut();
  await app.press("id:home-settings");
  await app.waitFor("当前：相册墙");
  await app.press("id:settings-cabinet");
  await app.waitFor("当前：唱片柜");
  await app.press("id:close-panel");
  await app.waitFor("id:gallery-cabinet");
  expect(app.shows("id:gallery-wall")).toBe(false);
  await pullOut();
  await app.press("旅行相册，2 张照片，查看相册详情");
  await app.press("id:detail-open");
  await app.waitFor("id:photo-wall");
});
