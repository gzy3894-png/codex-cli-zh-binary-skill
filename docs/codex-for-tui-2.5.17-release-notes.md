# Codex for TUI 2.5.17

2.5.17 是 2.5.16 后的原生 `/resume` 列表热修：会话文件虽已跨中转共享，但 Codex TUI 会按**当前站 `model_provider`** 过滤 SQLite `threads`，历史行仍带旧站 provider id 时会显示「还没有会话」。本版在 materialize / seed-shared-sessions 时自动把各 runtime 的 `threads.model_provider` 重标为该站当前 provider。

## 修复内容

- 新增 `restamp_runtime_thread_providers` / `restamp_all_runtime_thread_providers`：按 runtime `config.toml` 的 `model_provider` 更新其 `sqlite-builds/*/state_5.sqlite` 中 `threads.model_provider`。
- `materialize_runtime` 在写完 runtime config 后对全部 runtime restamp，保证切站启动后列表可见。
- `seed-shared-sessions` CLI 在共享 sessions 链接修复后一并 restamp；新增 `restamp-thread-providers` 运维入口。
- 不改写 rollout jsonl 正文；仅改 per-runtime SQLite 索引，便于各站各自过滤通过。
- 版本同步：`versionName=2.5.17`、`versionCode=83`、runtime epoch `apk-2.5.17`。

## 验收重点

- 覆盖安装后打开 App，切换任意中转/配置档（含 grok 站）后启动 Codex。
- worker 内原生 `/resume`（不手动加 `--all`、保持「当前目录」过滤）：每个站应看到与共享 inventory 一致的非空列表（同 cwd 下条数一致）。
- 原先在 grok 等站显示 0 条、主站正常的场景，切过去应恢复可见。
- 2.5.16 的 sessions 共享符号链接语义保持不变。

## 版本

- `versionName=2.5.17`
- `versionCode=83`
- runtime epoch：`apk-2.5.17`
- 包名：`com.gzy3894.codexfortui`
