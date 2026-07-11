# Codex for TUI 2.5.5 发布说明

Codex for TUI 2.5.5 前滚修复 2.5.0–2.5.4 侧栏「老终端窗口删不掉」：关窗必须先更新注册表，再杀 PTY。

## 核心修复

### 1. 关窗顺序：registry/map 先于 native teardown

2.5.2–2.5.4 已把侧栏定义为终端窗口（PTY），并修了 Compose 关窗闪退。但 `terminateSession` 仍先 `finishIfRunning()` 再 `notifyTerminated()`。

若 PTY native 路径崩溃/进程被杀：

1. 磁盘 `session-isolation/registry.json` 仍保留该窗口；
2. 下次冷启动 `pendingRestoreIfEmpty` 把旧窗口全部复活；
3. 用户体感「删除无效 / 老会话删不掉」。

2.5.5 顺序：

1. 快照 `remainingBefore` 并切换 `currentSession`（最后一窗置 `""`，不伪造 `main`）
2. 从 live `sessions` / `sessionList` 移除
3. `notifyTerminated` **立即持久化** registry 删除
4. 最后 best-effort `finishIfRunning` + 清理 temp

仍不 `clearAll` / `stopSelf`（EXIT 通知栏路径除外）。关窗 ≠ 删除 codex/claude CLI 对话。

### 2. 保留 2.5.4

- 配置档共享 `sessions` / `history`（软链控制 `CODEX_HOME`）
- shell 与 `codex` 统一 `CODEX_FOR_TUI_WORKSPACE`
- `closeWindow` + `Handler.post` 延后 terminate，避免 Compose 点击帧 map 突变

## 版本信息

- `versionName=2.5.5`
- `versionCode=71`
- runtime epoch：`apk-2.5.5`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.5 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装。

## 安装后建议自测

1. 覆盖安装 2.5.5 后打开侧栏，对 **升级前遗留** 的窗口逐个点删除：条目消失且不闪退。
2. 强杀 App 再冷启动：已删除窗口 **不应** 复活。
3. 最后一个窗口关掉后 App 仍在，可再「+」新建。
4. 切换不同 Codex 配置：CLI 会话列表仍共享。
5. `pwd` 在 shell 与 `codex` 启动路径均为 `/root/workspace`（或 `CODEX_FOR_TUI_WORKSPACE`）。
