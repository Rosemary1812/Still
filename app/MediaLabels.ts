import type { Photos } from "contactsheet/native";

type Item = ReturnType<typeof Photos.library>["photos"][number];

export function mediaName(item?: Item) {
  switch (item?.kind) {
    case "video": return "视频";
    case "live": return "实况照片";
    default: return "照片";
  }
}

export function itemLabel(item: Item | undefined, fallback: string) {
  if (!item?.title) return fallback;
  return item.kind === "video" || item.kind === "live" ? `${item.title}，${mediaName(item)}` : item.title;
}

export function thisItem(item?: Item) {
  return (item?.kind === "video" ? "这段" : "这张") + mediaName(item);
}

export function albumCount(ids: string[], lookup: (id: string) => Item | undefined) {
  let videos = 0;
  for (const id of ids) if (lookup(id)?.kind === "video") videos++;
  const photos = ids.length - videos;
  if (!videos) return `${photos} 张照片`;
  return photos ? `${photos} 张照片、${videos} 段视频` : `${videos} 段视频`;
}

export function importSummary(result: Awaited<ReturnType<typeof Photos.addFiles>>) {
  const parts = [];
  if (result.added) parts.push(`已添加 ${result.added} 项`);
  if (result.existing) parts.push(`${result.existing} 项已在相册中`);
  if (result.skipped) parts.push(`${result.skipped} 个文件无法读取`);
  return parts.join("，");
}
