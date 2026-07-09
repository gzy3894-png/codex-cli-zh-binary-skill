# Codex for TUI 2.3.10 发布说明

Codex for TUI 2.3.10 是 2.3.9 的文件托盘缓存生命周期热修版。

## 修复

- 修复 App 退出重进、进程重启或覆盖安装后，文件托盘 UI 变空但 App 本地临时图片、视频、文本和浏览器截图残留不可见的问题。
- App 冷启动会恢复仍有 refs 且文件存在的托盘项目；缺失 refs、过期、超限或不可读的孤儿缓存会被清理。
- 文件托盘“清空”、单项删除、Agent clear 和超过托盘上限的自动淘汰都会同步删除 App 本地临时副本与 refs。
- `codex-clean` 覆盖文件托盘 refs 与浏览器截图缓存，继续只在 `apply` 阶段移动到可恢复 trash。

## 兼容性

- `codex-preview path <编号>`、文件托盘 status/events/result 和现有发送短引用协议保持兼容。
- 清理范围只限 App 本地缓存目录，不会删除用户从系统文件管理器选择的原始文件。
- 正式包名仍为 `com.gzy3894.codexfortui`。

## 版本与验证

- 版本：`versionName=2.3.10`，`versionCode=53`
- 本地门禁：shell 语法检查、`tests/codex-for-tui-static-guards.sh`、`tests/codex-for-tui-ops-smoke.sh`。
- Release APK 仍由 GitHub Actions 使用正式签名 Secrets 构建，并校验包名、版本、非 debuggable 和正式证书指纹。

## 回滚

Android 不支持普通覆盖安装降级；从 2.3.10 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
