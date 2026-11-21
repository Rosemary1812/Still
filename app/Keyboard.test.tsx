import { expect, open, test } from "nsh/test";

// Run KeyboardSeed.test.tsx headlessly first with the same isolated STILL_LIBRARY_DIR.
test("Escape leaves each note field and restores photo navigation", async () => {
  const app = await open("./App.tsx", { platform: "macos", width: 920, height: 680 });
  await app.press("宿主验收，2 张照片，查看相册详情");
  await app.press("id:detail-open");
  await app.waitFor("id:photo-wall");
  await app.press("id:album-read");
  await app.waitFor("01 / 2");
  await app.keyboard.press("right");
  await app.waitFor("02 / 2");
  await app.keyboard.press("left");
  await app.waitFor("01 / 2");
  for (const field of ["reader-title", "reader-date", "reader-location", "reader-story"]) {
    const value = `键盘回归 ${field}`;
    await app.type(`id:${field}`, value);
    await app.keyboard.press("escape");
    expect(app.shows("id:photo-reader")).toBe(true);
    await app.keyboard.press("right");
    await app.waitFor("02 / 2");
    await app.keyboard.press("left");
    await app.waitFor("01 / 2");
    expect(app.value(`id:${field}`)).toBe(value);
  }
});
