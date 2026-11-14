# ContactSheet NSH 原型

NSH 固定为 0.5.0，界面使用 TSX，单一 Rust 播放器在主窗口、展示窗口和托盘间共享。此原型不读写旧版相册数据库，也不修改原始照片。

## 原型范围

- 三张内置测试图片，或通过系统文件选择器加载本地 JPEG/PNG。
- 独立展示窗口；上一张、下一张、每 5 秒播放；关闭主窗口后继续播放，托盘菜单重开或退出。
- macOS 上点击 `Load latest Apple photo` 后申请照片权限，读取最近一张可访问照片并生成临时展示副本。
- 原型播放列表仅在内存中保存。本地文件直接引用，正式版再实现受管理导入目录与 SQLite。
- Rust 后台线程持有唯一播放时钟。TSX 每 200 毫秒读取版本，仅有变化时更新共享 signal；后续换成原生事件订阅。

## macOS

需要 Xcode、Rust stable 与 NSH 0.5.0。当前工作区使用 `.tools/` 中的隔离工具链，运行：

```sh
prototype/scripts/nsh-macos.sh check App.tsx
prototype/scripts/nsh-macos.sh test --target macos
prototype/scripts/nsh-macos.sh run App.tsx --target macos
prototype/scripts/nsh-macos.sh package App.tsx --target macos
```

Photos 权限应在打包应用中验证，应用标识为 `local.contact-sheet.nsh-prototype`，与旧版分开。

## Windows

在 Windows 11 x64 上安装 Rust stable、Visual Studio Build Tools 的 C++ 桌面开发工作负载和 Windows SDK，并安装 LLVM。安装 NSH 的固定版本：

```powershell
$env:NSH_VERSION = 'v0.5.0'
irm https://nsh.dev/install.ps1 | iex
```

重新打开 Developer PowerShell，在原型目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1 -Action check
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1 -Action test
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1 -Action run
powershell -ExecutionPolicy Bypass -File .\scripts\run-windows.ps1 -Action package
```

`-ExecutionPolicy Bypass` 仅作用于该 PowerShell 进程，不更改系统设置。Windows 编译会排除 Swift 桥接，UI 不显示 Apple Photos 按钮。

## 手动验收

1. 点击 `Load samples`，显示三张内置图片中的第一张。
2. 点击 `Open display`，在两个窗口切换上一张和下一张，确认同步。
3. 开始播放，关闭主窗口；展示窗口继续每 5 秒切换。
4. 从托盘重新打开主窗口，确认状态一致；关闭并重新打开展示窗口，不增加播放器。
5. 选择含中文、空格的本地图片路径，确认正确显示；取消选择时保留原列表。
6. Mac 上测试 Photos 的允许与拒绝路径；Windows 上测试真实文件选择器与系统托盘。
7. 通过托盘 `Quit` 退出，确认进程终止。

当前验证结果见 `../docs/nsh-prototype-status.md`。编译通过不能代替 Windows 真机运行。
