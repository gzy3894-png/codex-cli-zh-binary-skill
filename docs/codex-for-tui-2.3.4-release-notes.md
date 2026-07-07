# Codex for TUI 2.3.4 发布说明

Codex for TUI 2.3.4 是 2.3.3 的状态字段热修版。

## 修复

- 修复协作浏览器在 `codex-browser open` 成功后，同一个 `request_id` 的 `status/result` 被后续 WebView snapshot 回调覆盖成 `action=snapshot` 的问题。
- 修复后，`codex-browser open` / `codex-browser result <request_id>` 会保留显式动作，例如 `action=navigate`；snapshot 仍可用于加载中状态和独立快照，不再覆盖已完成的显式动作结果。

## 验证

- 2.3.3 安装态完整 smoke 已通过，确认浏览器 open/userscript 阻塞问题已修复。
- 本版本新增静态门禁，防止 snapshot 持久化再次覆盖同 request 的显式动作结果。

## 回滚

- 2.3.4 使用正式包名 `com.gzy3894.codexfortui`，`versionCode=47`，继续沿用 2.x 正式 APK 签名证书 SHA-256 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`。
- Android 不支持普通覆盖降级安装；从 2.3.4 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
