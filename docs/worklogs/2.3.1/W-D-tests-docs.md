# Worker D 测试与文档工作日志

日期：2026-07-07

## 范围

- 只修改 Worker D 独占范围：
  - `tests/codex-for-tui-static-guards.sh`
  - `tests/codex-for-tui-ops-smoke.sh`
  - `docs/codex-for-tui-2.3.1-ops.md`
  - `docs/worklogs/2.3.1/W-D-tests-docs.md`
- 未修改 README。
- 未运行 Gradle/APK。

## 已完成

1. 在静态门禁中新增 2.3.1 运维命令守卫：
   - `codex-doctor`
   - `codex-clean`
   - `codex-ops`
2. 新增 ops smoke：
   - 校验三类命令资产存在并兼容 `sh`；
   - 校验 `codex-clean scan` 默认不删除；
   - 校验 `codex-clean apply --yes --all` 移动到 trash；
   - 校验 `codex-clean restore` 能恢复；
   - 注入 API key、Bearer、cookie、refresh token、query token，校验 doctor/clean/ops 输出不泄露敏感值；
   - 校验 `codex-ops status/events/resume_hint` 可安全执行。
3. 新增 2.3.1 运维文档，写清：
   - 断线恢复步骤；
   - 清理前 scan、清理 apply、误清理 restore 的回滚流程；
   - 不得清理的敏感配置和用户文件边界；
   - 本地非 APK 门禁命令。

## 已运行命令

```sh
sh -n tests/codex-for-tui-static-guards.sh
sh -n tests/codex-for-tui-ops-smoke.sh
git diff --check
if grep -n '[[:blank:]]$' tests/codex-for-tui-ops-smoke.sh docs/codex-for-tui-2.3.1-ops.md docs/worklogs/2.3.1/W-D-tests-docs.md; then exit 1; fi
sh tests/codex-for-tui-ops-smoke.sh
sh tests/codex-for-tui-static-guards.sh
```

结果：

- Worker D 初次运行时，ops smoke/static guards 预期失败在缺少 `codex-doctor` 等资产。
- 主控整合 Worker A 后，`tests/codex-for-tui-ops-smoke.sh` 已通过。
- 全量 static guards 等待主控最终复跑。
- 未运行 Gradle/APK。

## 待整合注意

- `tests/codex-for-tui-static-guards.sh` 现在要求 APK assets 与 `MkSession` 管理列表包含 `codex-doctor`、`codex-clean`、`codex-ops`、`codex-ops-lib`。
- `codex_install_app_bridge_wrappers` 已把三类命令加入 wrapper 安装列表。
- ops smoke 期望 `codex-clean apply --yes --all` 非交互执行，并将可清理文件移动到包含 `/trash/` 且保留原文件名的路径。
