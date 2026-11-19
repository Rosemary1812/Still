import { expect, open, test } from "nsh/test";

// This flow can run on the real Win32 host without blocking on an OS picker.
test("desktop toolbar switches views and opens album creation", async () => {
  const app = await open("./App.tsx", { platform: "windows", width: 920, height: 680 });
  await app.press("id:home-wall");
  await app.press("id:home-settings");
  await app.waitFor("当前：相册墙");
  await app.press("id:settings-cabinet");
  await app.waitFor("当前：唱片柜");
  await app.press("id:close-panel");
  await app.press("id:home-add");
  await app.waitFor("id:album-name");
  await app.press("id:close-panel");
  expect(app.shows("id:home-settings")).toBe(true);
});
