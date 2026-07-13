# Codex for TUI 2.5.18

2.5.18 是 2.5.17 后的原生 `/resume` 列表热修。2.5.17 只重标 SQLite `threads.model_provider`，但 Codex 启动会从 rollout `session_meta` backfill 索引，旧站 provider 会把列表再次滤空。

## 修复内容

- 启动 materialize / `seed-shared-sessions` / `restamp-thread-providers` 时执行 Codex++ 风格 **双写**：
  1. 改写共享 `sessions/**`、`archived_sessions/**` 中 rollout 的 `session_meta.payload.model_provider` 为当前站 provider；
  2. 把各 runtime `sqlite-builds/*/state_5.sqlite` 的 `threads.model_provider` 重标为同一 provider；
  3. 将 `has_user_event=0` 的行修复为 `1`（可见性兜底）。
- 这样即使 Codex 再 backfill，也会从已改写的 session_meta 写入正确 provider，原生 `/resume`（当前目录）可列出共享会话，无需 `--all`。
- 不改会话正文、UUID、cwd；仅同步 provider 可见性字段。

## 版本标识

- `versionName=2.5.18`
- `versionCode=84`
- runtime epoch：`apk-2.5.18`
- Codex binary：`0.144.1-zh.1`（与 2.5.17 相同固定制品）

## 升级说明

覆盖安装本版 APK 后打开 App。首次启动会按新 epoch 完成 support/runtime 升级；进入任一中转站后原生 `/resume` 应显示共享会话列表。若仍为空，在启动台执行一次配置修复或重新打开 Codex 窗口，使 materialize 再次跑 provider 同步。
