import type { Photos } from "contactsheet/native";

export function importSummary(result: Awaited<ReturnType<typeof Photos.addFiles>>) {
  const parts = [];
  if (result.added) parts.push(`已添加 ${result.added} 项`);
  if (result.existing) parts.push(`${result.existing} 项已在相册中`);
  if (result.skipped) parts.push(`${result.skipped} 个文件无法读取`);
  return parts.join("，");
}
