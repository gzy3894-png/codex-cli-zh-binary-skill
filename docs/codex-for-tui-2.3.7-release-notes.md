# Codex for TUI 2.3.7 发布说明

Codex for TUI 2.3.7 是基于 2.3.6 稳定基线的上下文监测小版本。本版本只增加上下文自动检测、压缩来源记录和本会话压缩次数监测，不继承 `origin/context-monitor-v2.3.7` 废案。

## 新增

- `codex-context status` 新增给 Agent 读取的检测信号，`PreCompact auto` 触发后会标记 `agent_prepare_required=true`。
- `PreCompact` 与 `PostCompact` 分别维护压缩开始和压缩完成计数；压缩来源按 `local/remote/unknown` 记录。
- 新增 `session_compact_count` 和 `session_compact_local_count`、`session_compact_remote_count`、`session_compact_unknown_location_count`，用于报告当前会话压缩次数。
- `SessionStart` 继续记录 `startup/resume/compact/unknown` 类型计数，便于判断 compact 后新会话是否已经触发。
- 新增 `codex-context report` 与 `codex 上下文监测` 手机端入口。默认用户报告只显示“几点几分触发了一次本地/远程压缩，当前会话已压缩 X 次”。

## 边界

- 计数来源只来自 Codex hook 输入事件；没有读取、扫描或改写 session/transcript 文件。
- 本版本不做 token 估算，不推断没有 hook 事件证明的压缩。
- 官方 Codex hook matcher 只公开 `manual/auto` 触发原因；本版本会优先读取 hook 输入中的 `compact_location`、`compactLocation`、`location`、`origin`、`source` 等来源字段，无法确认时记录为 `unknown`，不伪造本地/远程判断。

## 版本与发布

- 正式包名：`com.gzy3894.codexfortui`
- 版本：`versionName=2.3.7`，`versionCode=50`
- 正式签名证书 SHA-256 继续校验为 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`

## 验证

本地门禁覆盖：

- `sh -n android-app/core/main/src/main/assets/codex-context`
- `sh -n android-arm64-musl/lib/codex-zh-local.sh`
- `sh tests/codex-for-tui-static-guards.sh`
- 相关 installer/config/dev-transfer/ops smoke 测试

Android 不支持普通覆盖降级安装；从 2.3.7 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
