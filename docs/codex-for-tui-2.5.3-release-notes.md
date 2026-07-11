# Codex for TUI 2.5.3 发布说明

Codex for TUI 2.5.3 修正「终端窗口」与「agent 会话」的产品边界，并修复侧栏删除窗口闪退。

## 核心模型（重要）

侧栏列表是 **终端窗口**（类似 PowerShell 多开窗口），只对应一个可关闭的终端进程 / PTY。

- **关闭窗口** = 结束该窗口的 shell/PTY，去掉标签。
- **不是** 删除 codex/claude 的 agent 会话历史。
- Agent 前缀 / 首条消息命名只是窗口的显示标签，不把侧栏变成 agent 会话列表。
- Agent resume UUID（若有）独立于「关窗口」；关窗口不会也不应抹掉 CLI 侧对话记录。

## 用户可见变化

1. **删除/关闭窗口不再闪退**  
   侧栏关闭按钮、快捷键关闭、shell 退出后的窗口清理走统一 `closeWindow` 路径。

2. **关闭 = 关窗口**  
   不再在关闭最后一个窗口时 `stopSelf()` / 强制 `finish()` Activity（这是闪退竞态来源）。  
   关掉当前窗口会切到仍存活的其它窗口；全部关掉后可再点「+」新建。

3. **文案对齐**  
   侧栏标题改为「终端窗口」；重命名说明强调仅显示名，不绑定 agent 会话。

## 相对 2.5.2

- 保留 2.5.2：自动 Agent 前缀、首条消息命名、EXIT 清注册表、冷恢复、createSession 不误盖 identity。
- 纠正把侧栏当 agent 会话列表的行为偏差；关闭路径与 agent 生命周期解耦。

## 版本信息

- `versionName=2.5.3`
- `versionCode=69`
- runtime epoch：`apk-2.5.3`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.3 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装。
