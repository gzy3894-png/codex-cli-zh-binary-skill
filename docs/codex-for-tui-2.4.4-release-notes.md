# Codex for TUI 2.4.4 发布说明

Codex for TUI 2.4.4 是 2.4.3 的前滚热修版，恢复文件托盘发送图片/文件时的「附加说明」对话框。

## 关键修复

### 文件托盘发送缺少附言入口

自 2.3.9 起，文件卡片点击「发送」会直接提交，不再弹出「发送文件 / 附加说明（可选）」对话框。  
后端 `sendPreviewToAi(preview, userMessage)` 一直支持附言，但 UI 被硬编码为 `onSendToAi(preview, "")`，导致多版无法附加说明。

2.4.4 恢复：

- 点击文件卡片「发送」→ 弹出 `SendPreviewDialog`
- 可填写「附加说明（可选）」；留空仍可直接发送
- 附言会进入提示词、panel event 与 session fold 摘要
- 文本托盘 `TextComposerTile` 不受影响，仍是独立输入后发送

2.4.3 的 `code_mode_only` / 工具调用修复继续保留。

## 仍保留的能力

- 2.4.2 起的离线、原子、可回滚完整环境升级
- 固定 Codex `0.144.1-zh.1` ARM64 musl 二进制
- profile 独立 runtime / sessions / SQLite
- `apk-2.4.4` runtime epoch
- musl 上规范化 `tool_mode`，`gpt-5.6-*` 走普通 shell 工具路径

## 升级方式

已安装 2.4.3 或更早版本的用户：

1. 从 GitHub Releases 下载并覆盖安装 2.4.4 APK。
2. 打开 App，等待首次 APK 环境升级完成。
3. 打开文件托盘，选择图片/文件，点「发送」，确认出现附加说明对话框；可留空发送。

无需手动运行 `codex 更新`、`codex-local repair-launcher` 或手工改 `CODEX_HOME`。

## 版本与固定产物

- `versionName=2.4.4`
- `versionCode=59`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.4`

Android 不支持普通覆盖安装降级。从 2.4.4 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
