# Codex for TUI 2.5.7 发布说明

Codex for TUI 2.5.7 将侧栏从“终端窗口列表”升级为 Codex/Claude 对话管理器，并补齐配置删除一致性与 PTY 关闭生命周期。

## 核心改动

### 1. Codex/Claude 对话恢复

- 自动扫描 Alpine home 下的 Codex `sessions/**/rollout-<uuid>.jsonl` 与 Claude `.claude/projects/**/*.jsonl`。
- 对话 registry 单独保存于 `filesDir/conversation-isolation/registry.json`，保留显示名、来源、工作目录、最后活动时间和归档状态。
- 用户输入 `codex` / `claude` 后，扫描新建 transcript 并把真实 UUID 绑定到当前终端窗口；显式 `codex resume <uuid>` / `claude --resume <uuid>` 立即绑定。
- 选择历史对话时复用已绑定窗口，或创建新 PTY 并注入正确的 resume 命令。
- 关闭 PTY 窗口不会删除 CLI transcript 或对话 registry；对话只支持归档，不提供永久删除。

PTY 滚屏内容和关闭时尚未提交的输入不属于 CLI 会话恢复范围。

### 2. PTY 关闭稳定性

- 关闭前先把窗口从 live map 和窗口 registry 移除。
- 当前 TerminalView 在最后一个窗口关闭时先 `attachSession(null)`，避免 native reader/emulator 清理期间继续回调已脱离窗口。
- 重复点击或 restore/create 竞态会复用正在运行的 PTY，并对关闭中的窗口做幂等保护。

`SIGSEGV` 属于进程级 native 崩溃，Kotlin `try/catch` 无法捕获；本版本通过解绑、状态先落盘和幂等 teardown 降低触发路径，最终设备压力回归仍是发布完成条件。

### 3. 配置一致性

- runtime 物化固定为 `common ⊕ managed ⊕ runtime-local`。
- control `config.toml` 删除通用字段后，旧 runtime 不会再把该字段写回。
- `profile sync-runtime` 将明确的 runtime-local 字段保存到独立 overlay。
- 无 active profile 时切换压缩策略也会立即持久化 `runtime_managed.root_keys` 到 `index.json`。

## 版本信息

- `versionName=2.5.7`
- `versionCode=73`
- runtime epoch：`apk-2.5.7`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖降级。从 2.5.7 回退必须发布更高 versionCode 的前滚修复包，或卸载重装。

## 安装后建议自测

1. 覆盖安装 2.5.7，确认旧 Codex/Claude 历史出现在“对话”抽屉。
2. 选择一个历史对话，确认执行 `codex resume <uuid>` 或 `claude --resume <uuid>` 并恢复上下文。
3. 关闭终端窗口后重新打开 App，确认对话仍在且可以再次打开。
4. 删除 control 通用配置项并切换 profile/relaunch，确认该项不会从旧 runtime 复活。
5. 连续创建、切换、关闭多个窗口，确认没有幽灵窗口或已关闭窗口复活。
