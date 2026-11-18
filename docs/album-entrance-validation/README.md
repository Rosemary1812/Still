# 相册入场回落 · 2026-11-15

进入相册架时，封面依次出现在搁板上方，再加速下落并向后靠稳。打开客户端与从照片墙返回目录都会播放；普通视图更新不重播。

## 参考

实看 [Shopify Editions](https://www.shopify.com/editions)，重新加载后采样 80 帧，覆盖约 1.6 秒：先出现架子，再出现悬空封面，随后逐本落下。

读取当日公开页面的 `albumConstants-CGvpvu9n.js` 与 `(_locale).editions._index-DpnXB8xC.js`。常量为 75 ms 错峰、400 ms 初始等待、400 ms 下落。`OM` 的封面出现时间是 `400 + index × 75` ms，随后再等待 `index × 75` ms 调用落下；`DM` 使用 easeInQuart 下落，旋转在下落开始 240 ms 后启动。

## 实现

- 使用现有 SwiftUI 封面，起点抬高 22 点，下落后以底边为支点后倾 9 度，阴影同步收紧。
- 封面出现增加 60 ms 淡入；其余分段时序沿用参考。不是 WebGL 材质的逐像素复刻。
- 最多采用前 10 本的错峰时长，避免大资料库出现长时间等待。
- 入场结束前暂不响应相册操作，避免与抽出动画交叠。系统减少动态效果开启时直接显示落定状态。
- 视图任务取消时恢复可交互状态，避免重新出现后卡在入场中。
- `scripts/preview-album-shelf.swift` 增加“重播入场”，只在内存示例客户端出现。

## 验证

最终开发版 Debug 构建通过。已有 6 项测试全部通过，覆盖相册关系、存储、导入和播放；这些测试不证明动画的视觉效果。最终 diff whitespace 检查通过。

独立预览使用生产 `LibraryView` / `AlbumGallery` 与 12 本内存相册、只读样片。通过原生视图缓存导出 36 帧，确认从空架子到封面落定的渲染状态。见 [原生渲染帧](native-render-filmstrip.jpg)。导出会影响采样间隔，不能当作原速录屏或精确动画性能证据。

ScreenCaptureKit 两次返回 -3811，未完成真实窗口录屏、按钮点击和减少动态效果的系统级验收。现有详情返回路径本轮未重新进行 UI 自动操作。

构建日志：`/tmp/still-entrance-build-final.log`。测试日志：`/tmp/still-entrance-tests.log`。

原有 `design-engineering-library/` 和同时出现的相册按钮尺寸调整保留，未纳入本次动效的修改范围。未提交或推送。
