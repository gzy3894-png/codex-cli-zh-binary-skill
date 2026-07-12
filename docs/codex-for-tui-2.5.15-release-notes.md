# Codex for TUI 2.5.15

2.5.15 是 2.5.14 后的 P0 前滚热修：修复启动台/侧栏用 `PendingCommand` 走 `/bin/sh -lc` 导致的语法错误、把旧 Codex 会话物理导入当前 runtime 供原生 `/resume` 枚举，并堵住配置模式/runtime 的连环嵌套。

## 修复内容

- 启动台输入 `codex` / `claude` / `grok` 时，创建普通交互 worker 窗口，再把命令写入 worker PTY；不再通过 `PendingCommand` + `/bin/sh -lc` 注入。
- 侧栏历史/对话恢复同样改为 worker PTY 输入 resume 命令，消除 `/bin/sh[1]: syntax error: unexpected ')'`。
- 启动 Codex 前，把 control home、旧 profile/runtime 中的 rollout 物理复制到当前 `runtime_home/sessions`；同 UUID 同内容跳过，内容冲突不覆盖并记入 journal。
- 若进程内 `CODEX_HOME` 已落在 `config-runtimes/*`，配置模式与 `prepare_runtime` 会先回到 control home，避免 `config-runtimes` 连环嵌套。
- 配置引擎拒绝嵌套 runtime 路径；配置模式增加重入保护。
- 版本同步：`versionName=2.5.15`、`versionCode=81`、runtime epoch `apk-2.5.15`。

## 验收重点

- 覆盖安装后打开 App，在启动台输入 `codex`：应新建 worker 并在其中启动 Codex，启动台本身保持兜底 shell。
- 侧栏点开旧会话：不应再出现 `/bin/sh[1]: syntax error: unexpected ')'`。
- 在 worker 里执行原生 Codex `/resume`：应能看到升级前已有的会话（含 7 月旧 rollout，若本机仍存在）。
- 运行 `codex 配置模式`：可正常管理配置；不应在 runtime 下再套一层 `config-runtimes`。
- 配置模式运行中再次进入应被拒绝，而不是连环菜单。

## 版本

- `versionName=2.5.15`
- `versionCode=81`
- runtime epoch：`apk-2.5.15`
- 包名：`com.gzy3894.codexfortui`
