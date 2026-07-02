# Codex for TUI 配置问题记录

日期：2026-07-01

本文档记录用户反馈过的问题、前序修复尝试导致或暴露的新问题、以及当时仍未解决的问题。

> 2026-07-02 追加说明：本文档中的“状态更新”是一次失败修复尝试的阶段记录，不再代表当前可信状态。后续又出现了配置值污染、更新链路失败、`model_catalog_json` 生成非法 JSON schema 等问题。完整事故记录见 `codex-for-tui-failure-log-2026-07-02.md`。

## 2026-07-02 状态更新

这些问题已按“启动不变更配置、更新显式触发”的方向重构：

1. 普通 `codex` 启动只执行本地二进制，不再调用 preflight、profile refresh、脚本更新或 `/models` 刷新。
2. APK bootstrap 在检测到本地 `codex` 后直接 `exec codex`；只有首次未安装并经用户确认，或显式 `--update-scripts/update` 才拉取脚本。
3. 脚本更新改为独立命令：`codex-update check` 和 `codex-update apply`。
4. 第三方模型目录刷新改为独立命令：`codex-local refresh-models`，只更新 `model_catalog_json`，保留当前 `model` 和 `model_reasoning_effort`。
5. API Key 写入 `auth.json`，第三方 provider 通过 command auth 读取；不把 key 写入 `config.toml`。
6. 当时将旧脚本移入过 `backup/legacy-scripts-20260702/`；该备份目录已在后续清理中从仓库删除，历史仍保留在 Git 历史和已发布 Release 中。

## 用户遇到的问题

1. 第三方模型配置没有按预期生效。
2. Codex 只识别 `config.toml` / `conf.toml` 中的当前模型；`model_catalog_json` 中的模型没有成为实际运行时选择的模型。
3. 在 TUI 内执行 `/model`，进入“全部模型”，选择对应模型和思考等级后，界面流程可以完成，但选择结果没有在后续启动中保持。
4. TUI 内选择模型后，实际调用仍使用旧模型或默认模型。
5. 用户手动编辑 `~/.codex/config.toml` / `~/.codex/conf.toml` 后，启动链路仍会把该文件改回脚本生成的内容。
6. 用户手动编辑 `~/.codex/api-profiles/<profile>/config.toml` 后，该 profile 配置也可能被后续逻辑重新生成或覆盖。
7. `api-profiles` 中的配置会覆盖外部 `~/.codex/config.toml`，同时 `api-profiles` 自身的配置又会被其他生成逻辑覆盖。
8. 用户无法稳定地用自己手写的配置进行一次干净启动。
9. 每次重新进入或重启 App 时，会重复进入更新、恢复、预检、配置应用或配置刷新链路。
10. 启动路径包含 bootstrap、resume、preflight、profile refresh、profile apply 等多层脚本状态。
11. 便捷配置入口与手动编辑配置文件的使用方式发生冲突。
12. 用户测试中，真机环境表现与本地测试结果不一致。
13. 本地测试不是用户真机环境，也不是用户项目的真实运行环境。
14. 本地 Codex 环境也受到同一套脚本和配置状态影响。
15. 前序沟通中出现过用户询问“为什么需要推送”和“为什么需要 APK”的情况。
16. 用户需要在真机上关闭脚本链路，使用自己的配置启动一次。
17. 用户需要 Codex 从 `auth.json` 读取 key，而不是把 key 写入 `config.toml`。

## 修复尝试导致或暴露的新问题

1. 添加或生成 `model_catalog_json` / `model_catalog.json` 后，第三方模型可以出现在模型目录相关配置中，但没有解决实际运行时模型选择的持久化问题。
2. 增加 `--refresh-current-profile`、`--preflight-select` 等入口后，启动链路增加了新的自动执行路径。
3. 增加启动时自动刷新当前 profile 后，启动过程会访问 `/models`，并重新生成 profile 配置或 live 配置。
4. 增加 live config 与 profile config、`default-model`、模型列表之间的同步后，配置覆盖方向变多。
5. 增加 profile 管理、编辑、删除、模型刷新后，除 `config.toml` 外的配置状态文件数量增加。
6. `write_codex_config` 会根据 `default-model`、`models.txt`、`enabled-models.txt`、API base、auth、`/models` 输出等信息重新生成配置。
7. profile 配置可以覆盖 `~/.codex/config.toml`，而 profile 配置本身又可以被生成逻辑覆盖。
8. 为了保存 `/model` 选择，把 live config 回写到 profile 的尝试增加了 live config 与 profile config 之间的写入路径。
9. 本地 smoke test 可以通过，但用户真机上的配置持久化问题仍存在。
10. 后续临时改动尝试减少启动自动刷新或菜单重写，但没有形成用户接受的最终方案。
11. 前序修复过程中产生了未提交的脚本和测试改动：
    - `android-arm64-musl/codex-local-resume.sh`
    - `tests/codex-for-tui-installer-smoke.sh`

## 重构前仍未解决的问题

以下条目是 2026-07-01 问题归档时的未解决状态。2026-07-02 的当前处理结果见本文开头“状态更新”。

1. 尚未形成用户接受的最终架构或实现。
2. 日常 `codex` 启动路径尚未完成重新设计。
3. 尚未确定 `~/.codex/config.toml` 是否作为唯一当前运行时配置来源。
4. 尚未确定 `api-profiles` 的长期角色：快照、缓存、还是主动配置源。
5. 尚未确定 `model_catalog_json` 更新时如何避免覆盖用户选择的 `model` 和 `model_reasoning_effort`。
6. 尚未完成安装、初始化、profile 管理、模型刷新、日常启动命令之间的职责拆分。
7. 尚未建立基于真机环境的验证方式。
8. 尚未完成对已有受影响用户配置的迁移方式。
9. 尚未确认真机上关闭脚本链路并使用用户自有配置启动的固定入口。
10. 尚未确认 `auth.json` 读取 key 的最终配置写法和启动链路。

## 相关文件

1. `android-arm64-musl/codex-local-resume.sh`
2. `android-arm64-musl/codex-for-tui-bootstrap.sh`
3. `android-arm64-musl/install-reterminal-alpine.sh`
4. `android-arm64-musl/install-alpine-proot.sh`
5. `tests/codex-for-tui-installer-smoke.sh`
6. `android-arm64-musl/README.md`

## 相关配置与状态名称

1. `~/.codex/config.toml`
2. `~/.codex/conf.toml`
3. `~/.codex/auth.json`
4. `~/.codex/model_catalog.json`
5. `model_catalog_json`
6. `~/.codex/api-profiles/<profile>/config.toml`
7. `~/.codex/api-profiles/<profile>/default-model`
8. `~/.codex/api-profiles/<profile>/models.txt`
9. `~/.codex/api-profiles/<profile>/enabled-models.txt`
10. `~/.codex/api-profiles/last-profile`
11. `--refresh-current-profile`
12. `--preflight-select`
