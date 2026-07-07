# Codex for TUI 2.3.3 发布说明

Codex for TUI 2.3.3 是 2.3.2 的安装后真机调试热修版，重点修复浏览器导航被 userscript 回调阻塞、事件流过滤和开发迁移包默认导出问题。

## 修复

- 修复 `codex-browser open` 在页面已经加载成功后仍等待 userscript 回调，导致真机上误报 `Page load timed out before userscript completion` 的问题。现在主框架完成即可让导航请求返回 `state=done`，userscript 继续异步执行并记录日志，不再阻塞后台浏览器自动化。
- 修复 `codex-panel events files/browser`、`codex-preview events`、`codex-browser events` 事件过滤不严格的问题，避免文件托盘和浏览器事件互相混入，降低 Agent 状态误判。
- 修复 `codex-dev-transfer export` 默认安全导出可能因为 `/root/.codex/.tmp/plugins` 临时缓存、symlink 或 pack 文件权限而失败的问题。默认导出和 `--include-secrets` 均排除 `.codex/.tmp`，默认导出继续排除 auth、Cookie、WebView/db/no_backup/browser 等敏感状态。

## 验证

- 本地只运行轻量 shell/static/smoke 门禁，不本地构建 APK/Gradle。
- 已运行：`git diff --check`、`tests/codex-for-tui-static-guards.sh`、`tests/codex-for-tui-dev-transfer-smoke.sh`、`tests/codex-for-tui-dev-transfer-security-smoke.sh`、`tests/codex-for-tui-config-smoke.sh`、`tests/codex-for-tui-ops-smoke.sh`、`tests/codex-for-tui-installer-smoke.sh`。
- 2.3.2 安装态真机 smoke 在跳过浏览器后通过；浏览器完整 smoke 需要安装 2.3.3 APK 后复测，因为本次核心修复位于 App/Kotlin 端。

## 回滚

- 2.3.3 使用正式包名 `com.gzy3894.codexfortui`，`versionCode=46`，继续沿用 2.x 正式 APK 签名证书 SHA-256 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`。
- Android 不支持普通覆盖降级安装；从 2.3.3 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
