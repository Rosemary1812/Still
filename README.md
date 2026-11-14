# Still

![Still](docs/branding/still-logo.png)

一款本地 macOS 相册应用：管理多本相册，以流动照片墙浏览照片，点击查看和编辑旁注，也可切换双页阅读。

## 原生客户端

当前主实现位于 `Sources/ContactSheet`，使用 SwiftUI 和 SwiftData，需要 macOS 14+ 和 Xcode。

- 从本地文件或 Apple Photos 导入照片，保存受管理的照片副本。
- 多本相册、封面目录、四行流动照片墙。
- 照片标题和多段旁注编辑、双页阅读。
- 相册关系与描述保存在本机；开发版和正式版使用独立资料库。

```sh
# 单元测试
scripts/test.sh

# Debug 构建
scripts/build.sh

# 独立资料库的相册开发版
scripts/build-albums-dev.sh

# Release 构建
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ContactSheet.xcodeproj -target ContactSheet \
  -configuration Release SYMROOT="$PWD/build" build
```

Release 产物为 `build/Release/Still.app`。这些是本地构建，尚未作为公证安装包发布。构建产物与用户相册数据库不纳入版本管理。

## 目录

- `Sources/`、`Tests/`：原生应用与测试。
- `scripts/`：项目生成、构建和测试脚本。
- `docs/album-flow-validation/`：验收记录与截图，包含截图工具的已知限制。
- `previews/photo-albums/`：早期 HTML 相册原型、样片及其来源记录。
- `prototype/`：独立 NSH / Rust 跨平台技术原型，尚非当前正式客户端。

当前范围不包含桌面小组件。Apple Photos 导入及 Windows 原型仍需进一步实机验收；本地文件导入、旁注保存和重启恢复已验证。摄影样片的来源见 `previews/photo-albums/photo-sources.json`。

应用显示名称为 Still；为兼容已保存的相册，bundle ID 和内部工程目标仍沿用原标识。图标源文件与打包说明见 `docs/branding/README.md`。
