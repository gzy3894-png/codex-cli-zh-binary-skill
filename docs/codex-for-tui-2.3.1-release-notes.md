# Codex for TUI 2.3.1 Release Notes

发布日期：2026-07-07

## 重点

2.3.1 是稳定底座版本，面向已经在使用 2.x 的正式版用户。覆盖安装后重新打开终端，新会话会自动同步新增桥接命令。

## 新增

- `codex-doctor`：只读环境诊断，检查 PREFIX、ops 状态目录、基础工具、Codex CLI、配置入口、认证文件存在性和桥接 assets。
- `codex-clean`：可回滚清理。`scan` 默认只扫描；`apply` 只移动到 `$PREFIX/local/ops/trash/<task_id>/`；`restore` 可恢复；`purge --yes` 才永久删除。
- `codex-ops`：查看运维任务 `status/events/summary/resume-hint`，断线后可用来恢复上下文。

## 加固

- files/browser/session/perf 状态补齐 `schema_version`、`timestamp_ms`、`needs_user`、`user_action` 等统一字段。
- 浏览器 session log 只写 timestamp/request/state/action/ok 摘要，避免记录 URL、token 或 cookie。
- 终端 perf 状态增加平均/最大帧耗时、慢帧、输入事件和近期合帧计数。
- GitHub Actions 正式 release 签名只接受 `ANDROID_RELEASE_*` GitHub Secrets，缺失任一 secret 必须失败；仓库内不再提供 keystore/testkey fallback。
- Release APK 上传前校验 packageName、versionCode、versionName、`debuggable=false` 和正式签名证书 SHA-256。

## 升级

1. 从 GitHub Releases 下载 2.3.1 正式 APK。
2. 覆盖安装到既有正式版。
3. 重新打开 Codex for TUI。
4. 在终端运行：

```sh
codex-doctor
codex-clean scan
codex-ops status
```

普通启动仍不会自动更新脚本、刷新模型目录或覆盖用户手写配置。需要更新脚本时手动运行 `codex 更新`。

## 回滚

- APK 回滚：Android 普通覆盖安装不能降低 `versionCode`，因此不能把 2.3.1（`versionCode=44`）直接覆盖安装回 2.3.0（`versionCode=43`）。需要回滚时请优先发布“前滚回滚包”（保留修复前行为但使用更高 `versionCode`），或在明确会丢失/需迁移数据的情况下卸载后重装旧版。
- 清理回滚：如执行过 `codex-clean apply <scan_task_id>`，用输出里的 `apply_task_id` 运行：

```sh
codex-clean restore <apply_task_id>
```

不要手动删除 `$PREFIX/local/ops/trash/`，除非确认不再需要恢复。
