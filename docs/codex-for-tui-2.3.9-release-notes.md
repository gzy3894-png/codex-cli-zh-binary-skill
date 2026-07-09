# Codex for TUI 2.3.9 发布说明

Codex for TUI 2.3.9 是 2.3.8 的文件托盘热修版。

## 修复

- 修复文件托盘文本框点击“发送”后，`文本[编号] 路径：codex-preview path <编号>` 只停在 Codex 输入框、不自动提交的问题。
- 修复文件卡片点击“发送”仍需要二次确认的问题；现在点击后直接把短文件引用发送到当前会话。
- 发送链路会先写入短引用，再延迟触发真实 Enter，避开 Codex TUI 对同 tick 粘贴/提交的防护路径。

## 兼容性

- `codex-preview path <编号>` 解析方式不变。
- 文件 refs、`status/events/result` 和 session fold 记录保持兼容。
- 正式包名仍为 `com.gzy3894.codexfortui`。

## 版本与验证

- 版本：`versionName=2.3.9`，`versionCode=52`
- 本地已运行 `git diff --check` 和目标静态门禁。
- Release APK 仍由 GitHub Actions 使用正式签名 Secrets 构建，并校验包名、版本、非 debuggable 和正式证书指纹。

## 回滚

Android 不支持普通覆盖安装降级；从 2.3.9 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
