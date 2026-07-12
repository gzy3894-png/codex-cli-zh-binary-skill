# Codex for TUI 2.5.12

2.5.12 是 2.5.11 后的 P0 前滚热修，解决历史会话仍不可恢复、旧工作区历史被 cwd 过滤，以及 App 重建误入失效 worker 窗口的问题。

## 修复

- 历史窗口的 PendingCommand 固定走 `/system/bin/sh → init-host → /bin/sh -lc`，不再把 Alpine 内不存在的裸 `sh` 传给 `init-host`。
- 侧栏恢复 Codex UUID 时执行 `codex resume --all -C /root/workspace <uuid>`；用户直接运行 `codex resume` 也会自动补充 `--all`。
- Activity 或 TerminalView 被系统重建时始终附着不可删除的固定启动台；运行中的 worker 仍保留在侧栏，但不会抢占 App 入口。

## 旧历史迁移

首次覆盖安装会执行一次参数化、事务型迁移：

- canonical `/root/.codex/sessions/**/*.jsonl` 只改首条 `session_meta.payload.cwd` 的 `/root → /root/workspace`。
- 所有 live control/profile/runtime `state_5.sqlite` 的 `threads.cwd` 同步迁移。
- 旧 `config-profiles` 与 `config-runtimes` 中尚未进入 canonical 目录的 Codex rollout，按真实 `payload.id` 去重复制到共享 `sessions/`；源副本不删除。
- UUID、对话正文、mtime 和权限位保持；迁移逐文件校验正文 SHA-256，SQLite 使用 backup API、`BEGIN IMMEDIATE` 和 `quick_check`。
- 升级保留 manifest 与 SQLite 回滚备份；失败或进程中断会在重试前恢复，后续 APK 步骤失败也会联动回滚。
- 相同 UUID 如果出现内容冲突，迁移会停止并回滚，不会猜测覆盖。

迁移恢复的是 Codex CLI 会话，不是旧 PTY 的滚屏、尚未提交的输入或进程内状态。

## 安装

从本 Release 下载 `app-release.apk`，覆盖安装后打开 App，等待“环境升级完成”并进入启动台。不要降级覆盖安装，也不需要额外运行 `codex-update`。

## 版本

- `versionName=2.5.12`
- `versionCode=78`
- runtime epoch：`apk-2.5.12`
- Codex CLI：`0.144.1` 中文版，`aarch64-unknown-linux-musl`
