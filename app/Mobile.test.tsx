import { expect, open, test } from "nsh/test";

const image = new Uint8Array([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,2,0,0,0,144,119,83,222,0,0,0,12,73,68,65,84,120,156,99,208,13,74,4,0,1,144,0,225,231,109,252,87,0,0,0,0,73,69,78,68,174,66,96,130]);

test("mobile picker cancellation, retry, rename and accessible landscape shelf", async () => {
  const app = await open("./MobileEntry.tsx", { platform: "ios", width: 844, height: 390 });
  let attempts = 0;
  app.onPick(() => {
    attempts++;
    if (attempts === 1) return null;
    return [{ name: "one.png", data: attempts === 2 ? new Uint8Array([1]) : image }];
  });
  await app.press("新建相册");
  await app.type("id:mobile-name", "日光");
  await app.press("创建并选择照片");
  await app.waitUntil(() => attempts === 1 && !app.shows("正在处理…"));
  await app.press("返回");
  await app.waitFor("新建相册，加入第一张照片。");
  await app.press("新建相册");
  await app.type("id:mobile-name", "日光");
  await app.press("创建并选择照片");
  await app.waitFor("id:mobile-error");
  expect(app.shows("id:mobile-name")).toBe(true);
  await app.press("创建并选择照片");
  await app.waitFor("id:mobile-photo-1");
  await app.press("重命名");
  await app.clear("id:mobile-name");
  await app.type("id:mobile-name", "湖岸");
  await app.press("保存名称");
  await app.waitFor("湖岸");
  await app.press("id:mobile-photo-1");
  await app.press("编辑旁注");
  await app.type("id:mobile-note-title", "清晨");
  await app.press("保存旁注");
  await app.waitFor("清晨");
  await app.press("返回");
  await app.press("返回");
  await app.waitFor("id:mobile-album-list");
  await app.setViewport(390, 844);
  await app.waitFor("id:mobile-album-stack");
  await app.press("label:打开相册：湖岸");
  await app.waitFor("id:mobile-photo-1");
  await app.press("删除相册");
  await app.press("确认");
  await app.waitFor("新建相册，加入第一张照片。");
});
