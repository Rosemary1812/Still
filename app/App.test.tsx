import { expect, open, test } from "nsh/test";

test("create an album, switch the gallery view, read and annotate", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  async function pullOut() {
    await app.press("远方，3 张照片，查看相册详情");
    await app.waitFor("id:detail-open");
    await app.press("id:detail-close");
    await app.waitUntil(() => !app.shows("id:album-detail"));
  }
  await app.press("id:home-add");
  // One Escape closes the panel, though the name field holds the focus.
  await app.type("id:album-name", "不要了");
  await app.keyboard.press("escape");
  await app.waitUntil(() => !app.shows("id:album-panel"));
  await app.press("id:home-add");
  await app.type("id:album-name", "旅行相册");
  await app.press("id:save-album");
  // A new album opens on its own page; nothing covers it.
  await app.waitFor("id:album-empty");
  expect(app.shows("id:album-panel")).toBe(false);
  const selection = new URL("./native/tests/picker-fixtures", import.meta.url).href.replace(/^asset:/, "file://");
  await app.dropFiles("id:album-empty", [selection]);
  await app.waitFor("id:photo-wall");
  // One unreadable file is reported and does not cost the rest of the selection.
  await app.waitFor("已添加 2 项，1 个文件无法读取");

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

  // The album name is edited where it is shown.
  await app.press("id:album-title");
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
  await app.waitFor("2 项已在相册中");

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
  // The view is chosen where it is seen: the toolbar's switcher is the only control for it.
  expect(app.shows("id:home-settings")).toBe(false);
  await app.press("id:home-cabinet");
  await app.waitFor("id:gallery-cabinet");
  expect(app.shows("id:gallery-wall")).toBe(false);
  await pullOut();
  await app.press("远方，3 张照片，查看相册详情");
  await app.press("id:detail-open");
  await app.waitFor("id:photo-wall");
});

test("the wall's photo menu", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  await app.press("id:home-add");
  expect(app.enabled("id:save-album")).toBe(false);
  await app.type("id:album-name", "一页");
  await app.submit("id:album-name");
  const selection = new URL("./native/tests/fixtures/first.png", import.meta.url).href.replace(/^asset:/, "file://");
  await app.dropFiles("id:album-empty", [selection]);
  await app.waitFor("id:photo-wall");
  await app.rightClick("label:查看照片 1 >> nth=0");
  expect(app.menu()?.map(item => item.label)).toEqual(["查看照片", "已是相册封面", "从相册移除…"]);
  await app.chooseMenuItem("查看照片");
  await app.waitFor("01 / 1");
  await app.keyboard.press("escape");
  await app.waitFor("id:photo-wall");

});
