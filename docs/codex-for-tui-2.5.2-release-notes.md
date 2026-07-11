# Codex for TUI 2.5.2 发布说明

Codex for TUI 2.5.2 在 2.5.1 之上修正会话隔离的产品语义，并消化 2.5.1 审查中确认的接线问题。

## 用户可见变化

1. **不再手选 Agent 前缀**  
   添加会话对话框只选 Alpine / Android。新标签默认 `shell-…`。

2. **启动 agent 时自动更新前缀**  
   在 shell 中执行 `claude` / `codex`（及常见 wrapper）后，当前标签前缀自动变为 `claude-` / `codex-`。同一标签里退出后再启动另一种 agent，前缀会跟着更新。

3. **首条有效消息自动命名**  
   软键盘 / 虚拟输入栏 / 文件托盘发送的首条非噪音内容会命名标签（例如「你好」→ `claude-你好`）。纯启动命令与常见 shell 噪音不会占用命名。手动重命名后不再自动覆盖。

4. **通知栏 EXIT 清空标签**  
   EXIT 会清空会话注册表；下次打开不再复活刚退出的标签。进程被系统杀死仍可按注册表冷恢复。

## 审查修复

- `createSession` 默认不再用 CODEX 覆盖恢复中的 Claude/Shell 元数据（`preserveExistingIdentity`）。
- 冷恢复后不再在已有恢复列表旁强行再造 `main`。
- `changeSession` 也会做一次 UUID resume 注入（仍依赖已绑定的 `agentResumeId`）。
- 恢复路径去掉「EXIT 后仍 allRecords 复活」的误恢复。

## 已知限制（保留）

- 仍不自动从 CLI 输出解析并绑定 resume UUID。
- 不恢复终端 transcript 全文。
- 不做 per-session `CODEX_HOME`。

## 版本信息

- `versionName=2.5.2`
- `versionCode=68`
- runtime epoch：`apk-2.5.2`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.2 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装。
