# Codex for TUI 2.3.11 发布说明

Codex for TUI 2.3.11 是 2.3.10 的文件托盘桥接竞态热修版。

## 修复

- 修复 `codex-preview clear` / `codex-panel clear files` 等控制请求的发布竞态：App 处理 `clear` 时会清理 `local/media-preview/queue`，2.3.10 中 shell 端可能还没来得及把 `.req.tmp` 改名成 `.req`，从而出现 `mv ... No such file or directory`。
- `codex-preview`、`codex-panel`、`codex-browser`、`codex-session` 现在都先在 bridge 根目录写完整临时请求，再复制并发布到 `queue/*.req` 与 legacy `request`，避免监听目录/清理目录里的半成品文件被 App 抢先处理或删除。
- 保留 2.3.10 的文件托盘缓存生命周期修复：重启恢复有效缓存、清理孤儿缓存，清空/单删/Agent clear/自动淘汰同步删除 App 本地副本。

## 验收重点

- `codex-preview clear installed_smoke_clear` 不再报 `mv ... No such file or directory`。
- 文件托盘图片、长文本、视频、浏览器截图仍能通过 `codex-preview path <id>` 解析到 App 本地缓存。
- `codex-panel clear files` / `codex-preview clear` 后，`local/media-preview/files`、`refs`、`queue` 和 `local/browser/screenshots` 不留下不可见残留。

## 版本与回滚

- 版本：`versionName=2.3.11`，`versionCode=54`
- 包名：`com.gzy3894.codexfortui`
- 正式签名证书 SHA-256：`a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`

Android 不支持普通覆盖安装降级；从 2.3.11 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
