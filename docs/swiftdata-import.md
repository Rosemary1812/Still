# 把 Mac 上的旧 Still 相册带到 NSH 客户端

首次打开新版前，在仓库根目录运行：

```sh
python3 scripts/migrate-swiftdata.py --destination "$HOME/Library/Application Support/StillNSH"
```

默认读取沙盒 `local.contact-sheet.app` 的 `default.store`、`ContactSheet/Imports` 和偏好设置。迁移可在旧客户端开启时读取 SQLite 的一致快照；迁移期间请勿继续编辑旧相册，迁移后两个库不会同步。只在目标目录尚未建立时执行首次导入。如果已经使用了新版，可将 `--destination` 指向其他新目录，通过 `STILL_LIBRARY_DIR` 启动查看；不要删除现用图库。相同快照再次执行只报告已迁移，既有 NSH 数据不会被覆盖。

使用开发容器或导出的数据库时，明确指定来源；有 WAL 时请使用原始存储位置，或用 SQLite backup 得到完整数据库，不要单独复制 `.store`：

```sh
python3 scripts/migrate-swiftdata.py \
  --source '/path/to/default.store' --imports '/path/to/Imports' \
  --preferences '/path/to/old.plist' --destination '/path/to/new-library'
```

脚本保留相册 UUID、展示顺序、每本相册的照片顺序和封面，以及共享照片的标题、说明、日期和地点。旧网格模式对应新版照片墙。旧照片的原始字节按 SHA-256 校验后复制到 `media/`；数据库通过外键和完整性检查后，才将整个临时库改名到目标位置。`legacy-import.json` 保留原始精度的时间戳、相册成员记录 ID 和此次快照的指纹。此文件含私有相册信息，请随图库保管。

仅保存在系统「照片」中的项目没有本地 `Imports` 文件。脚本如遇 `photo:` 标识会列出需要导出的项目并停止。可从「照片」导出对应原图，准备 JSON 文件（键为报错中的完整标识，值为原图绝对路径），再附加 `--apple-files /path/to/exports.json` 重试。脚本不会为丢失、损坏或无法识别的照片生成占位记录。可识别的格式为 JPEG、PNG、GIF、WebP、HEIC；实际显示仍取决于目标平台的解码能力。

验证：`python3 scripts/test-swiftdata-migration.py` 使用临时目录测试带 WAL 的旧库、跨相册共享、同图不同注释、重复导入和失败时的数据保护。
