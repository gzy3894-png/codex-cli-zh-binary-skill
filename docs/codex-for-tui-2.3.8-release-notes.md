# Codex for TUI 2.3.8 发布说明

Codex for TUI 2.3.8 是 2.3.7 的用户时区热修版。

## 修复

- `codex-context report` / `codex 上下文监测` 在 Android 环境中优先使用 `/system/bin/date` 格式化“几点几分”，避免 Alpine/proot 默认 UTC 导致用户侧压缩报告时间偏移。
- 非 Android 环境仍保留普通 `date` 和 `date -r` 兜底，便于本地脚本验证。

## 不变边界

- 仍然只记录 Codex hook 事件给出的压缩来源和本会话压缩次数。
- 仍然不读取、不扫描、不改写 session/transcript 文件。
- Agent 侧上下文检测信号不变；用户侧报告仍只显示最近一次压缩时间和当前会话压缩次数。

## 版本

- 版本：`versionName=2.3.8`，`versionCode=51`
- 包名：`com.gzy3894.codexfortui`
- 正式 APK 仍由 GitHub Actions 使用正式签名输入构建，并校验包名、版本号、非 debuggable 和签名证书 SHA-256。

## 验证

- 已安装环境热修验证：`codex-context report` 时间与 Android 系统时区一致。
- `sh -n android-app/core/main/src/main/assets/codex-context`
- `TMPDIR=/tmp RTK_DISABLED=1 sh android-app/core/main/src/main/assets/codex-context verify`
- `RTK_DISABLED=1 sh tests/codex-for-tui-static-guards.sh`
- `RTK_DISABLED=1 sh tests/codex-for-tui-installed-device-smoke.sh`

## 回滚

Android 不支持普通覆盖降级安装；从 2.3.8 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
