# Codex for TUI 2.5.9 发布说明

Codex for TUI 2.5.9 是针对 2.5.8 安装后设备回归的前滚修复包。

## 修复内容

- 修复 Codex rollout 使用 UUIDv7，而扫描器只接受 UUIDv1–v5，导致真实存在的 Codex JSONL 全部被过滤。
- 修复显式 `codex resume <uuidv7>` 无法从命令行绑定真实会话 UUID。
- 支持读取 Codex `event_msg/user_message` 的 `payload.message` 字符串作为会话标题。
- 对话抽屉拆分为“Codex 对话”“Claude 对话”“终端窗口”三个带数量的分区，每个分区可以独立折叠和展开。
- transcript 仍从 Alpine home 下的共享 `.codex/sessions` 与 `.claude/projects` 只读导入；不会删除历史，也不会修改用户 provider 或中转配置。

## 版本信息

- `versionName=2.5.9`
- `versionCode=75`
- runtime epoch：`apk-2.5.9`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖降级。从 2.5.9 回退必须发布更高 versionCode 的前滚修复包，或卸载重装。

## 安装后重点验证

1. 打开“对话”抽屉，确认 Codex、Claude 和终端窗口分别显示数量并可独立折叠。
2. 确认已有 Codex UUIDv7 历史出现在 Codex 分区，标题不是统一的“历史会话”。
3. 选择一个旧 Codex 对话，确认新建或复用窗口并执行 `codex resume <uuidv7>`。
4. 选择一个 Claude 对话，确认执行 `claude --resume <uuid>`，且不会混入 Codex 分区。
5. 关闭终端窗口后重新打开抽屉，确认历史对话仍保留。
