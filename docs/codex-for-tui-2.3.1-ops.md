# Codex for TUI 2.3.1 运维、断线恢复与清理回滚

日期：2026-07-07

目标：2.3.1 在不改变普通 `codex` 启动语义的前提下，增加只读诊断、运维状态查看和可回滚清理。普通启动仍不自动更新脚本、不刷新模型目录、不覆盖用户手写配置。

## 命令边界

| 命令 | 作用 | 约束 |
| --- | --- | --- |
| `codex-doctor` | 检查 Codex for TUI 环境、配置入口、桥接目录和常见状态 | 只读；输出必须脱敏，不打印 API key、token、cookie、`auth.json` 内容 |
| `codex-ops status` | 查看 App/脚本侧运维状态 | 安全可重复执行；缺状态文件时也应正常退出 |
| `codex-ops events` | 查看近期运维事件 | 只显示脱敏摘要；不输出敏感字段值 |
| `codex-ops resume_hint` | 给断线/重进 App 后的恢复提示 | 只给下一步建议，不自动执行更新、清理或配置重写 |
| `codex-clean scan` | 扫描可清理项 | 默认 dry-run，不删除、不移动 |
| `codex-clean apply --yes --all` | 执行清理 | 只把可清理项移动到 trash，不直接永久删除 |
| `codex-clean restore --latest` | 回滚最近一次清理 | 从 trash 恢复到原位置；实现可兼容 `restore latest` 或 `restore` |

## 断线恢复流程

1. 重新打开 Codex for TUI，先不要运行 `codex-update apply` 或 `codex-local refresh-models`。
2. 执行：

   ```sh
   codex-ops status
   codex-ops resume_hint
   ```

3. 按 `resume_hint` 检查：
   - 当前目录是否还是断线前的项目目录；
   - 是否有未完成的浏览器、文件托盘、会话折叠或登录任务；
   - 是否需要用户手动点开 App 内任务卡或 Custom Tabs。
4. 确认配置未被改写：

   ```sh
   codex-local status
   ```

5. 需要继续原会话时再启动 `codex`。如果提示登录，走设备码/任务卡流程；不要把 token、cookie 或 `~/.codex/auth.json` 内容粘贴给任何人。

## 清理与回滚流程

清理必须先扫描：

```sh
codex-clean scan
```

确认只包含 App 临时文件、桥接结果、旧事件日志或可再生成缓存后，再执行：

```sh
codex-clean apply --yes --all
```

执行后若发现误清理，立即恢复最近一次 trash：

```sh
codex-clean restore --latest
```

清理实现不得直接删除或移动这些内容：

- `~/.codex/auth.json`
- `~/.codex/config.toml` / `conf.toml`
- `~/.codex/AGENTS.md`
- 用户项目目录文件
- Android Download 中的用户文件

## 本地门禁

本地只跑 shell/static/smoke，不跑 Gradle/APK：

```sh
sh -n tests/codex-for-tui-ops-smoke.sh
sh tests/codex-for-tui-ops-smoke.sh
sh tests/codex-for-tui-static-guards.sh
git diff --check
```

`tests/codex-for-tui-ops-smoke.sh` 覆盖：

1. `codex-doctor`、`codex-clean`、`codex-ops` 资产存在且 `sh -n` 通过；
2. `codex-clean scan` 默认不删除；
3. `codex-clean apply --yes --all` 将目标移动到 trash；
4. `codex-clean restore` 可恢复；
5. doctor/clean/ops 输出不泄露测试注入的 API key、Bearer、cookie、refresh token；
6. `codex-ops status/events/resume_hint` 在缺少真实 App 状态时也安全可执行。
