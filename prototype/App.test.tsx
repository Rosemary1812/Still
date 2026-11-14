import { expect, open, test } from "nsh/test";

test("shared player follows controls in a second window", async () => {
  const app = await open("./App.tsx", { width: 920, height: 680 });
  await app.press("Load samples");
  await app.waitFor("3 images · Paused · 5 seconds per image");
  await app.screenshot(".nsh/verification/library.png");
  await app.press("Open display");
  await app.waitFor("Photo 1 / 3");
  await app.waitUntil(() => app.window("display").state()?.visible === true);
  await app.window("display").screenshot(".nsh/verification/display-initial.png");
  await app.press("id:display-next");
  await app.waitFor("Photo 2 / 3");
  await app.window("display").screenshot(".nsh/verification/display.png");
  await app.press("id:display-toggle");
  await app.waitFor("3 images · Playing · 5 seconds per image");
  await app.window("main").pressClose();
  expect(app.window("main").state()?.visible).toBe(false);
  expect(app.window("display").state()?.visible).toBe(true);
  await app.waitFor("Photo 3 / 3", { timeout: 8000 });
  await app.press("id:display-toggle");
});
