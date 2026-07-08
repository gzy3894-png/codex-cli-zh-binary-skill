# Codex for TUI 2.3.6 发布说明

Codex for TUI 2.3.6 是 2.3.5 的浏览器真机复测热修版。

## 修复

- 修复内置浏览器重复打开当前已加载根路径 URL 时，`https://example.com` 与 WebView 回调的 `https://example.com/` 被误判为不同加载目标，导致 `codex-browser open` 等到 `Page load timed out` 的问题。
- `codex-browser open`、安装后真机 smoke 和用户日常签到/登录脚本在重复打开同一根路径页面时会直接识别为当前页面已可用，不再误判失败。

## 保持不变

- 第三方 OpenAI-compatible 配置修复保持 2.3.5 行为：内部 provider id 仍为 `custom`，生成/修复后的 `[model_providers.custom].name` 为 `OpenAI`，用户手写 provider 名称不会被覆盖。
- 普通启动仍不会自动更新脚本、刷新模型目录或覆盖用户手写配置。
- 正式 APK 仍只通过 GitHub Actions 使用 2.x 正式签名构建，本地不构建 APK。

## 版本与回滚

- 2.3.6 使用正式包名 `com.gzy3894.codexfortui`，`versionCode=49`，继续沿用 2.x 正式 APK 签名证书 SHA-256 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`。
- Android 不支持普通覆盖降级安装；从 2.3.6 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
