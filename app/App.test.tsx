import { expect, open, test } from "nsh/test";

// The desktop runner supplies an isolated STILL_LIBRARY_DIR. Two valid tiny PNGs
// exercise the actual native importer and deduplication without a system picker.
const png = (variant: number) => new Uint8Array(variant ? [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 120, 184, 34, 20, 0, 4, 76, 1, 223, 246, 191, 20, 245, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130] : [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 208, 13, 74, 4, 0, 1, 144, 0, 225, 231, 109, 252, 87, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

test("create an album, switch both gallery controls, read, annotate and present", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  app.onPick(() => [{ name: "first.png", data: png(0) }, { name: "broken.png", data: new Uint8Array([1, 2, 3]) }, { name: "second.png", data: png(1) }]);
  async function pullOut() {
    await app.press("远方，3 张照片，查看相册详情");
    await app.waitFor("id:detail-open");
    await app.press("id:detail-close");
    await app.waitUntil(() => !app.shows("id:album-detail"));
  }
  await app.press("id:home-add");
  await app.type("id:album-name", "旅行相册");
  await app.press("id:save-album");
  // A new album opens on its own page; nothing covers it.
  await app.waitFor("id:album-empty");
  expect(app.shows("id:album-panel")).toBe(false);
  await app.press("id:empty-files");
  await app.waitFor("id:photo-wall");
  // One unreadable file is reported and does not cost the rest of the selection.
  await app.waitFor("已添加 2 张照片，1 个文件无法读取");

  await app.press("id:album-read");
  await app.waitFor("01 / 2");
  await app.keyboard.press("right");
  await app.waitFor("02 / 2");
  // Notes are written in place and save themselves.
  await app.type("id:reader-title", "湖边的早晨");
  await app.press("id:photo-cover");
  await app.waitFor("相册封面");
  // Escape hands the keyboard back from the note to the pages.
  await app.keyboard.press("escape");
  expect(app.shows("id:photo-reader")).toBe(true);
  await app.keyboard.press("left");
  await app.waitFor("01 / 2");
  expect(app.value("id:reader-title")).toBe("");
  await app.keyboard.press("right");
  await app.waitFor("02 / 2");
  expect(app.value("id:reader-title")).toBe("湖边的早晨");

  await app.press("id:album-play");
  await app.waitFor("id:display-next");
  await app.press("id:display-next");
  await app.waitFor("湖边的早晨");
  await app.press("id:display-edit");
  await app.type("id:note-location", "杭州");
  await app.press("保存描述");
  await app.waitFor("杭州");
  await app.window("display").pressClose();
  // What the display window saved shows in the album too.
  expect(app.value("id:reader-location")).toBe("杭州");

  // Album actions are a native menu; the name is edited where it is shown.
  await app.press("id:album-more");
  expect(app.menu()?.map(item => item.label)).toEqual(["重命名相册", "照片墙自动流动", "删除相册…"]);
  await app.chooseMenuItem("重命名相册");
  await app.clear("id:album-rename");
  await app.type("id:album-rename", "远方");
  await app.keyboard.press("enter");
  await app.waitFor("远方");
  expect(app.shows("id:album-rename")).toBe(false);

  // Dropped files and folders are imported; photos the album holds are not added twice.
  const folder = new URL("./native/tests/fixtures", import.meta.url).href.replace(/^asset:/, "file://");
  await app.dropFiles("id:photo-reader", [folder]);
  await app.waitFor("02 / 4");
  await app.dropFiles("id:photo-reader", [folder]);
  await app.waitFor("这些照片已经在相册里了");

  // Removing a photo asks with the system's alert.
  let asked = "";
  app.onDialog(dialog => { asked = dialog.title ?? ""; return "移除"; });
  await app.press("id:photo-remove");
  await app.waitFor("02 / 3");
  expect(asked).toBe("从相册移除这张照片？");

  await app.press("id:album-back");
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
  await app.press("远方，3 张照片，查看相册详情");
  await app.press("id:detail-open");
  await app.waitFor("id:photo-wall");
});

test("the wall's photo menu and deleting the album from its own menu", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  app.onPick(() => [{ name: "only.png", data: png(0) }]);
  await app.press("id:home-add");
  await app.type("id:album-name", "一页");
  await app.press("id:save-album");
  await app.press("id:empty-files");
  await app.waitFor("id:photo-wall");
  await app.rightClick("label:查看照片 1 >> nth=0");
  expect(app.menu()?.map(item => item.label)).toEqual(["查看照片", "已是相册封面", "从相册移除…"]);
  await app.chooseMenuItem("查看照片");
  await app.waitFor("01 / 1");
  await app.keyboard.press("escape");
  await app.waitFor("id:photo-wall");

  // Keeping the album is the answer Escape gives.
  app.onDialog(() => "取消");
  await app.press("id:album-more");
  await app.chooseMenuItem("删除相册…");
  expect(app.shows("id:photo-wall")).toBe(true);
  app.onDialog(dialog => { expect(dialog.title).toBe("删除「一页」？"); return "删除相册"; });
  await app.press("id:album-more");
  await app.chooseMenuItem("删除相册…");
  await app.waitFor("id:gallery-cabinet");
  expect(app.shows("一页")).toBe(false);
});
