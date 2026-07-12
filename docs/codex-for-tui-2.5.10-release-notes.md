# Codex for TUI 2.5.10

本版本修复 2.5.9 设备回归发现的 Agent 窗口串绑、历史内容错配和删除旧窗口闪退路径，并把窗口与对话改为平级、参数驱动的生命周期。

## 主要变化

- 进程冷启动固定创建一个不可删除的“启动台”，不再从注册表恢复旧 PTY。
- 只有明确的 Agent 启动命令会从启动台创建独立工作窗口；普通文本保留 Shell 语义，“+”仍创建额外 Shell。
- Claude 与 Grok 新会话在启动前生成 UUID 并传入 `--session-id`；Codex 使用每窗口 token 和 `SessionStart` hook 确定性绑定 UUID。
- 删除全局扫描“最新 JSONL”的推断路径，避免并发启动时把另一窗口的会话 UUID 绑定过来。
- 历史发现覆盖 `/root/.codex/sessions`、`/root/.claude/projects` 和 `/root/.grok/sessions`；点击历史按明确 UUID 创建 resume 工作窗口。
- 侧栏平级显示 Codex、Claude、Grok 历史分区、固定启动台和可折叠运行窗口。
- 用户关闭窗口先移除 UI/registry，再请求 SIGTERM；不会从用户关闭路径执行 `finishIfRunning()` 或 SIGKILL。
- 内置 Codex、Claude、Grok、Gemini、OpenCode、Qwen Code、Aider、Goose、Amp、Crush、Cursor Agent、Copilot 和 Z 识别；新增 `codex-agent` 管理自定义 Agent。
- 修复配置模式删除通用字段后被旧 runtime overlay 恢复；压缩策略在无 active profile 时同步持久化 `runtime_managed.root_keys`。

## 发布标识

- `versionName=2.5.10`
- `versionCode=76`
- SQLite/runtime epoch：`apk-2.5.10`
- Codex CLI：`0.144.1` 中文 ARM64 musl

APK 由 GitHub Actions 构建、正式签名并校验。安装后需要完成启动台、连续关窗、Codex/Claude/Grok 并发绑定、历史 resume 和自定义 Agent 回归。
