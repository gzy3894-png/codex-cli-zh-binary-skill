# Codex for TUI 2.5.4 发布说明

Codex for TUI 2.5.4 前滚修复 2.5.3 仍存在的关窗闪退，并落实「不同配置共享会话」与「工作区路径统一」。

## 核心修复

### 1. 关闭终端窗口不再闪退 / 不再清空会话

2.5.3 已把侧栏定义为终端窗口（PTY），但仍有关窗闪退与闪退后注册表被清空的路径。2.5.4：

- `closeWindow`：先切离将关闭的 PTY，再用 `Handler.post` 延后 `terminateSession`，避开 Compose 点击帧内的 map 突变。
- `terminateSession`：先快照 `remainingBefore` 并切换 `currentSession`，再杀进程；最后一个窗口时 `currentSession` 置为 `""`，不伪造 `main`，不 `clearAll` / `stopSelf`。
- 侧栏 `LazyColumn` 使用 sessions 快照，避免遍历 live map 时删除。

### 2. 不同配置共享会话（`model_providers.custom` 等）

- 每个配置档仍有独立的 `config-runtimes/*`（`config.toml` / `auth` / sqlite 隔离）。
- `sessions` / `history.jsonl` / `archived_sessions` / `shell_snapshots` **软链到控制 `CODEX_HOME`**，切换 profile 看到同一对话列表。
- 若运行时目录里已有私有 sessions，首次 materialize 会迁入控制 home 再改软链。
- 删除 profile **不会**删共享会话数据。

### 3. 工作区路径统一

- 交互 shell 与 `codex` launcher 都进入 `CODEX_FOR_TUI_WORKSPACE`（默认 `/root/workspace`）。
- 不再「纯 shell 落 `$HOME`、只有 codex 进 workspace」。

## 相对 2.5.3

- 保留：侧栏=终端窗口、自动 Agent 前缀、首条消息命名、EXIT 清注册表、冷恢复、ICU 安全命名。
- 关窗路径更硬；共享会话；工作区 cwd 统一。

## 版本信息

- `versionName=2.5.4`
- `versionCode=70`
- runtime epoch：`apk-2.5.4`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.4 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装。

## 安装后建议自测

1. 多开几个终端窗口，逐个点删除：不闪退；最后一个窗口关掉后 App 仍在，可再「+」。
2. 强杀 / 冷启动：窗口标签与 agent resume 绑定仍在（除非点过通知栏 EXIT）。
3. 切换不同 Codex 配置 / custom provider：`codex` 会话列表一致。
4. 打开 shell 与运行 `codex`：`pwd` 均为 `/root/workspace`（或 `CODEX_FOR_TUI_WORKSPACE`）。
