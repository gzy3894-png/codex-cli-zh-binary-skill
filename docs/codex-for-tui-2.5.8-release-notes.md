# Codex for TUI 2.5.8 发布说明

Codex for TUI 2.5.8 是 2.5.7 对话恢复实现的 CI 编译前滚修复包。

## 核心改动

2.5.8 保留 2.5.7 的全部用户可见修复：

- 自动扫描 Alpine home 下的 Codex `sessions/**/rollout-<uuid>.jsonl` 与 Claude `.claude/projects/**/*.jsonl`。
- 侧栏对话 registry 持久化真实 UUID；选择历史对话时复用窗口或新建 PTY 并执行正确的 resume 命令。
- 关闭 PTY 窗口只移除窗口 registry，不删除 CLI transcript；对话只支持归档。
- 关闭最后一个窗口前先 `attachSession(null)`，并以幂等状态顺序保护 native PTY teardown。
- 配置物化固定为 `common ⊕ managed ⊕ runtime-local`，control 删除通用字段不会从旧 runtime 复活。

本版本另外修复 `SessionBinder.createSession()` 缺少显式 `return` 导致的 Android Kotlin 编译失败。

PTY 滚屏内容和关闭时尚未提交的输入不属于 CLI 会话恢复范围。`SIGSEGV` 属于进程级 native 崩溃，设备压力回归仍是发布完成条件。

## 版本信息

- `versionName=2.5.8`
- `versionCode=74`
- runtime epoch：`apk-2.5.8`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖降级。从 2.5.8 回退必须发布更高 versionCode 的前滚修复包，或卸载重装。

## 安装后建议自测

1. 覆盖安装 2.5.8，确认旧 Codex/Claude 历史出现在“对话”抽屉。
2. 选择一个历史对话，确认执行 `codex resume <uuid>` 或 `claude --resume <uuid>` 并恢复上下文。
3. 关闭终端窗口后重新打开 App，确认对话仍在且可以再次打开。
4. 删除 control 通用配置项并切换 profile/relaunch，确认该项不会从旧 runtime 复活。
5. 连续创建、切换、关闭多个窗口，确认没有幽灵窗口或已关闭窗口复活。
