# Still

Still 是一款本地相册应用。macOS、Windows 和 iPhone 客户端使用 NSH 0.5.0。界面用 TSX 编写，相册、照片副本、旁注和播放状态由 Rust 管理。相册保存在当前设备。

## 开发

安装 NSH 0.5.0 和 Rust stable。Apple 平台需要完整的 Xcode；给 iPhone 模拟器或真机打包时，先用 rustup 安装对应的 Rust target（Apple Silicon 模拟器为 aarch64-apple-ios-sim，真机为 aarch64-apple-ios）。工作区已有 .tools 工具链时，启动脚本会自动选用它。

```sh
scripts/still run macos
scripts/still run ios
scripts/still check
scripts/still test macos
scripts/still package macos
scripts/still package ios-simulator
```

macOS 包生成在 `build/macos/Still.app`，模拟器包在 `build/ios-simulator/Still.app`。iPhone 真机包使用 `scripts/still package ios`，安装需要签名与 provisioning profile。Windows 请在装有 Visual Studio C++ 工具、Windows SDK、LLVM 和 Rust 的 Developer PowerShell 中执行 `app/scripts/run-windows.ps1 -Action run`；也支持 check、test 和 package。

## 图库升级

旧 Mac 客户端用户首次启动 NSH 版前运行：

```sh
python3 scripts/migrate-swiftdata.py --destination "$HOME/Library/Application Support/StillNSH"
```

迁移会复制相册、封面、顺序、照片和旁注，检查图片哈希后再启用新库。其他旧库路径和 Apple Photos 资源见[旧图库导入说明](docs/swiftdata-import.md)。iPhone 版沿用 local.still.ios 标识，升级后在已有应用沙盒中首次打开时导入旧图库。开发和测试可通过 `STILL_LIBRARY_DIR` 选择独立目录。

## 代码

- `app/App.tsx` 选择桌面或 iPhone 界面。桌面主页有唱片柜与相册墙、相册导入、照片阅读和独立放映窗口。
- `app/native/` 包含 SQLite 数据模型、媒体导入、播放器与 macOS 系统照片选择器桥接。
- `scripts/still` 是 Mac 与 iPhone 的开发入口。Windows 验证流程位于 `.github/workflows/windows.yml`。
