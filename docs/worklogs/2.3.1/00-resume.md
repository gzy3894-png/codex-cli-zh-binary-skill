# Codex for TUI 2.3.1 主控续连日志

日期：2026-07-07

## 当前目标

实施 2.3.1 稳定底座：`codex-doctor`、`codex-clean`、`codex-ops`，统一 bridge 状态字段，补充 perf 诊断，增加可回滚清理、任务日志和断线续连门禁。

## 分工与状态

- Worker A：CLI/脚本层，已完成 `codex-ops-lib`、`codex-doctor`、`codex-clean`、`codex-ops`。
- Worker B：Android bridge/status，已完成 `MainActivity.kt` 统一字段、续连去重和脱敏日志。
- Worker C：终端 perf，已完成 `TerminalBackEnd.kt` 轻量性能字段。
- Worker D：测试与文档，已完成 ops smoke、静态门禁和 2.3.1 ops 文档。
- 主控：已补齐 assets 同步、wrapper 安装、版本号 2.3.1、README 更新，并对齐 ops smoke 契约。

## 已知本地命令

```sh
RTK_DISABLED=1 sh tests/codex-for-tui-ops-smoke.sh
RTK_DISABLED=1 sh tests/codex-for-tui-static-guards.sh
RTK_DISABLED=1 sh tests/codex-for-tui-installer-smoke.sh
git diff --check
```

本地禁止运行 Gradle/APK 构建；APK 只走 GitHub Actions。

## 断线恢复步骤

1. `cd /root/codex-cli-zh-binary-skill`
2. `git status --short --branch`
3. 阅读本文件和 `docs/worklogs/2.3.1/W-*.md`。
4. 先跑 `sh tests/codex-for-tui-ops-smoke.sh`，再跑 static guards。
5. 若通过，再提交推送并盯 GitHub Actions release 构建。

## 尚未完成

- 全量本地非 APK 门禁复跑。
- GitHub Actions release 构建和正式签名校验。
- 真机安装后 smoke 和手动核验。
