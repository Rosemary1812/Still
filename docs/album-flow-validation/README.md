# 原生相册流程验收（2026-11-14）

本次在现有 SwiftUI / SwiftData 工程中实现，开发版使用独立 bundle ID `local.contact-sheet.albums-development`，不修改旧版资料库。未提交 Git；未实现桌面小组件。

## 已实现

- 多本相册目录、新建、重命名与导入。
- 四行方形照片墙，保留此前测量的 Mac Sleeve 行错位比例与统一向左流动节奏；支持暂停和横向拖动。
- 点击照片预览完整图片及旁注，编辑标题和多段描述；双页阅读、前后翻页和返回目录。
- 新导入图片复制到应用管理目录，按内容去重，原子写入；相册关系和描述由 SwiftData 保存。旧照片标识保持兼容。
- 少于四张的相册重复填充四行；只创建当前视口需要的照片墙单元。

## 验证结果

- `swift test --scratch-path /tmp/contactsheet-albums-build --disable-sandbox`：6 项测试通过。覆盖磁盘恢复、照片重复导入、源文件移除后副本可读、中文文件名、多段旁注、损坏图片拒绝、相册成员与播放逻辑、1–1001 张照片的行索引。
- `scripts/build-albums-dev.sh`：Xcode Debug 构建成功。
- 原生系统文件选择器实际导入 16 张 JPEG，创建“山野之间 · 验收”；另建“三张照片 · 验收”，导入 3 张。
- 实际编辑并保存“湖边，风刚停”及两段中文描述；检查预览、双页模式与下一页。
- 完全退出开发版，移动测试源文件目录，再启动。目录恢复 2 本相册（16 / 3 张）；照片能显示，标题和两段描述完整恢复。
- 最终开发版留在多相册目录，可直接继续体验。

## 截图与限制

- `native-wall.png`：首次原生验收照片墙截图。
- `native-library.png`、`native-book.png`：重启后捕获。系统捕获返回倾斜的缩略画面，不能作为最终视觉比例的验收依据；本轮重启后的状态和正文另由原生可访问性树核对。
- 实测的是本地文件导入；Apple Photos 选择器导入尚未实机验收。
- 1001 张仅验证行索引，不代表大量照片性能基准测试。横向拖动及键盘操作未做完整实机回归。

## 构建与运行

在工程根目录执行 `scripts/build-albums-dev.sh`。产物：`build-albums/Debug/Contact Sheet.app`。

测试日志：`/tmp/contactsheet-albums-test-final.log`；构建日志：`/tmp/contactsheet-albums-build-final.log`。测试用照片是既有原型素材的副本，未移动用户原始照片。
