# NSH 双平台原型验证记录

2026-11-13，分支 `codex/nsh-cross-platform`。Mac 与 Windows 原型均通过原生双窗口测试并完成打包。Windows 打包程序的人工验收尚未完成，远程操作工具连续返回 ScreenCaptureKit -3811/-3812 错误。

## 已完成

- NSH 0.5.0，发行包版本 `f4d68f7`，SHA-256 与官方校验文件一致。
- NSH TSX 界面、Rust 共享播放器、独立展示窗口、文件选择器和托盘菜单。
- macOS Photos 的 Swift C ABI 桥接；Windows 编译路径排除 Swift。
- 原 Swift 项目保留，原型不访问旧数据库；本地图片仅引用，播放列表不持久化。
- macOS 启动脚本、Windows PowerShell 运行脚本与原型 README。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Rust 播放器测试 | 2 项通过，覆盖计时切换、暂停、替换列表、空列表、上一张循环、单图不计时 |
| Rust crate 与 TSX 类型检查 | 通过 |
| NSH 官方模板 macOS 原生测试 | 1 项通过，确认工具链可操作原生窗口 |
| ContactSheet 原型 macOS 原生测试 | 1 项通过，8.9 秒；双窗口切图同步，隐藏主窗口后继续轮播 |
| macOS release 打包 | 成功，产物约 61 MB |
| ad hoc 签名校验 | `codesign --verify --deep --strict` 通过；未进行 Developer ID 签名和公证 |
| 打包应用启动 | 进程及真实窗口已确认 |
| 原生文件选择器 | 已选择含中文、空格路径的 PNG，并目视确认渲染 |
| 取消文件选择 | 保留原图片与播放列表 |
| Photos 桥接 | 点击后成功读取并显示最近一张可访问照片；未改动原图 |
| Windows Rust 与 TSX 检查 | 在 rosemary1812 上通过，NSH 0.5.0、Rust 1.99.1、Visual Studio 2022 与 Windows SDK |
| ContactSheet 原型 Windows 原生测试 | 1 项通过，0 失败；用例 10.2 秒，验证双窗口同步及隐藏主窗口后继续轮播 |
| Windows release 打包 | 成功生成程序目录和 ZIP；未安装 Inno Setup，因此未生成安装向导 |

原生测试第一次点击展示窗口失败，原因是文本已进入测试树，但原生窗口尚未挂载完成。测试增加对窗口可见状态的等待及截图后通过。测试同时显式使用桌面尺寸，避免默认手机尺寸导致布局裁切。

## 待验证

- Windows 打包应用启动、文件选择器与托盘的人工验收。原生开发宿主中的双窗口测试已通过。
- macOS Photos 被拒绝、照片仅在 iCloud、读取失败等路径。
- 托盘菜单重开窗口及退出的人工验收；主窗口隐藏后播放已由原生测试验证。
- 当前 200ms 状态轮询将在正式实现时改成事件订阅。

## 产物

- Mac 应用：`prototype/.nsh/out/Contact Sheet NSH Prototype.app`
- 主窗口截图：`docs/nsh-prototype-library.png`
- 展示窗口截图：`docs/nsh-prototype-display.png`
- Windows 源码传输包：`.transfer/ContactSheet-NSH-prototype.zip`
- Windows 程序目录：`C:\Users\wsmdm\Coding\ContactSheet-NSH-prototype\prototype\.nsh\out\Contact Sheet NSH Prototype`
- Windows ZIP：上述目录旁的 `Contact Sheet NSH Prototype.zip`
- Windows 安装及验证日志：`C:\Users\wsmdm\Coding\ContactSheet-NSH-prototype\setup.log`
- 操作说明：`prototype/README.md`

本机隔离工具链在 `.tools/`，构建缓存位于 `prototype/target/`、`prototype/native/target/` 与 `prototype/.nsh/`，均已加入忽略规则。当前无提交、无推送。
