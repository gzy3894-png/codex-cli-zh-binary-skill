# Codex for TUI 2.5.16

2.5.16 是 2.5.15 后的跨中转统一会话列表热修：无论使用哪套中转/配置档，原生 Codex `/resume` 都应看到同一完整会话列表（不依赖 CLI 注入 `--all` 才能“凑齐”列表）。

## 修复内容

- 深合并各 runtime 私有 `sessions` 树到 control home（同年/同月目录不再浅层跳过），再替换为指向 control 的共享符号链接。
- 错误或空的 symlink（例如指向 `config-profiles/*/sessions` 空目录）在启动/materialize 时重写到 control home。
- `materialize_runtime` 与启动路径会修复**全部** idle runtime，而不是只处理当前激活站。
- runtime session importer 先确保共享链接，再把其它 profile/runtime 中的 rollout 导入共享 sessions。
- legacy 配置导入不再把新 runtime 的 sessions 指到 legacy 目录；改为共享 control home，并吸收 legacy 私有 rollout。
- 版本同步：`versionName=2.5.16`、`versionCode=82`、runtime epoch `apk-2.5.16`。

## 验收重点

- 覆盖安装后打开 App，切换任意中转/配置档后启动 Codex。
- 在 worker 内执行原生 `/resume`（不手动加 `--all`）：每个站应看到同一完整列表（同 cwd 过滤结果一致）。
- 从原先只有 0 条或 1 条的站（含 `*-legacy` / grok 站）切过去，列表应恢复到与主站一致。
- 配置模式与 2.5.15 的启动台/侧栏 worker 路由行为保持不变。

## 版本

- `versionName=2.5.16`
- `versionCode=82`
- runtime epoch：`apk-2.5.16`
- 包名：`com.gzy3894.codexfortui`
