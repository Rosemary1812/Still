# Still

Still 是一款本地相册应用。macOS、Windows 和 iPhone 客户端使用 NSH 源码提交 `4a114852`。界面用 TSX 编写，相册、照片副本、旁注和播放状态由 Rust 管理。相册保存在当前设备。

相册可以混合保存照片、视频和 Live Photo。翻阅视频时直接在 Still 内播放；按住 Live Photo 可以播放动态部分。视频使用 MP4、MOV 或 M4V 容器，能否播放取决于设备的解码器。Apple 设备可从照片图库选择媒体，也可从文件导入；导出的 Live Photo 文件需要包含匹配标识才能自动配对。Windows 的文件导入将照片和视频作为独立条目。

普通 JPEG、PNG、GIF 和 WebP 保留导入的文件；Apple 设备将其他受支持的图片格式转换为 JPEG。Live Photo 保留静态和动态资源，并单独生成预览。将媒体从相册移除不会立即删除图库文件。

## 开发

安装 Rust stable。NSH 通过 `toolchain/nsh` 子模块固定到提交 `4a114852947a3ed486ad90b9d2dd22a0487a15f7`，启动脚本会初始化子模块并构建 CLI，应用原生依赖与 CLI 使用同一份源码。这个尚未发布的提交通过了 macOS 编辑后 Escape 与方向键回归测试；正式版 0.6.1 尚未通过该测试。Apple 平台需要完整的 Xcode；给 iPhone 模拟器或真机打包时，先用 rustup 安装对应的 Rust target（Apple Silicon 模拟器为 aarch64-apple-ios-sim，真机为 aarch64-apple-ios）。工作区已有 .tools 工具链时，启动脚本会自动选用它。

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
- `app/Reading.tsx` 是桌面端打开相册后的页面：`PhotoWall.tsx` 是流动照片墙，`Reader.tsx` 是翻阅页（照片与旁注并排，旁注就地编辑并自动保存）。相册内的操作不使用应用自绘弹窗：空相册可通过系统选择器添加照片，照片与文件夹可直接拖入窗口，移除照片使用系统确认框，结果提示显示在页面底部。
- `app/native/` 包含 SQLite 数据模型、媒体导入、播放器与 macOS 系统照片选择器桥接。
- `scripts/still` 是 Mac 与 iPhone 的开发入口。Windows 验证流程位于 `.github/workflows/windows.yml`。
