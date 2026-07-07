# Worker A CLI/脚本层工作日志

日期：2026-07-07

## 改动文件

- `android-app/core/main/src/main/assets/codex-ops-lib`
- `android-app/core/main/src/main/assets/codex-doctor`
- `android-app/core/main/src/main/assets/codex-clean`
- `android-app/core/main/src/main/assets/codex-ops`

## 已完成

- `codex-doctor`：只读/轻量写入自检，支持 `--json`，写入 status/events/summary/resume_hint。
- `codex-clean`：scan/apply/restore/purge/list-trash；scan 不删除，apply 移动到 trash，restore 可恢复，purge 必须 `--yes`。
- `codex-ops`：list/status/events/summary/resume-hint/path/doctor。
- `codex-ops-lib`：任务目录、JSON escape、脱敏、事件和恢复提示工具。

## 主控整合补充

- `codex-ops status/events/resume_hint` 支持无参查看默认/最近状态。
- `codex-clean apply --yes --all` 支持使用最近 scan。
- `codex-clean restore --latest` 支持恢复最近 trash。
- trash 保留原文件名到 `items/<序号>/<原文件名>`，便于人工核查。
