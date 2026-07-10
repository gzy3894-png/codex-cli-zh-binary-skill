# Codex for TUI 2.4.1 发布说明

Codex for TUI 2.4.1 是 2.4.0 的关键热修版，集中修复配置模式错误落入 Codex、迁移被运行数据卡死、不同站点会话互相污染、SQLite migration 校验和冲突，以及模型页和推理等级未严格绑定当前 Codex 构建的问题。

## 配置模式与迁移

- `codex 配置模式` 只配置、不启动 Codex。
- 迁移策略页输入 `b` 会直接返回 shell，不执行迁移。
- 迁移或配置操作报错时返回非零，并明确显示“未启动 Codex”，不会继续运行真实二进制。
- V1 迁移不再递归复制旧 profile 目录，只处理配置、认证、模型目录和官方登录 marker。
- SQLite、sessions、FIFO、插件缓存和 Git 临时对象保持原位，不进入迁移备份或 V2 配置档，避免 `Operation not permitted` 和特殊文件阻塞。

## 多站点并行会话

- 每个配置档有独立 runtime home。
- 每个 runtime 分别保存 `config.toml`、`auth.json`、`model_catalog.json`、sessions、history、archived sessions 和 shell snapshots。
- `AGENTS.md`、skills 和 rules 仍可作为静态能力从总目录共享；会话和运行状态不共享。
- 切换到另一个第三方站点后启动新 Codex，不会改写已经运行中的旧站点配置；旧进程退出时只同步回自己的配置档。
- 启动准备和退出同步的控制文件按启动器 PID 隔离，两个 Codex 同时启动或退出也不会互相覆盖结果。
- 删除配置会清理 runtime 中的配置和认证文件，但保留该配置已经产生的 session rollout，避免误删对话。

## SQLite 与 Codex 构建隔离

- SQLite 路径使用 `<profile-runtime>/sqlite-builds/<version>-<binary-sha>`。
- 不同配置不会共用 SQLite；相同版本但二进制构建不同也不会共用 SQLite。
- 独立路径同时写入 runtime `config.toml` 的 `sqlite_home` 并导出为 `CODEX_SQLITE_HOME`，避免旧配置中的 `sqlite_home` 优先级更高而继续指向旧数据库。
- 配置状态、V2 引擎或 runtime 生成失败时，启动器直接停止，不再回退到共享 `$CODEX_HOME`。

## 模型目录、推理等级与 `/model`

- Codex CLI 仍为 `0.144.1`，模型能力来源固定到 OpenAI Codex `rust-v0.144.1`：
  - commit：`44918ea10c0f99151c6710411b4322c2f5c96bea`
  - 上游模型目录 SHA-256：`dcab00231a5178a9c84b7aef4cc06a1e1359e37ee0dd7e69d5822c4b1de723b1`
- 配置引擎默认使用随包、与构建匹配的目录，不再读取 `openai/codex/main`。
- 第三方 `/models` 只提供可用模型 ID；默认推理等级、支持的 reasoning efforts、上下文窗口和自动压缩阈值从上述固定目录合并。
- 生成目录会把所有 `codex-auto-*` 辅助模型标记为 `visibility = "hide"`；条目仍可显式使用，但不会进入 picker。
- 2.4.0 已保存的 profile 目录会在启动物化时做同样的纯本地规范化，无需请求 `/models` 或自动刷新目录。
- Codex `0.144.1` 的原生 `/model` 在没有可见 auto 辅助模型时会直接进入完整可选模型页，因此本修复不修改或重新编译 Rust 二进制。

## 已完成门禁

- shell `sh -n`
- Python `py_compile`
- 配置 V2 smoke
- 配置 UI smoke
- 启动器与静态 guards
- 真实 Codex `0.144.1` 模型目录解析
- `git diff --check`
- 现有 Codex `0.144.1` 二进制解析目录门禁
- 已知、映射和未知 `codex-auto-*` 均隐藏的目录策略回归

发布前仍需在 GitHub Actions：

1. 构建、正式签名并验证 2.4.1 APK。
2. 运行安装后真机 smoke，确认 `/model` 首次进入即显示完整普通模型列表。
3. 重点复测两个不同站点的并行会话。

## 升级与版本

- 版本：`versionName=2.4.1`，`versionCode=56`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- APK 只通过 GitHub Actions 构建和发布；2.4.1 复用现有 `0.144.1-zh.1` 中文 Codex 二进制及原 SHA。

从 2.4.0 覆盖安装 2.4.1 后，重新打开终端。已完成首次安装的旧环境如需同步最新脚本和启动器，显式运行：

```sh
codex 更新
codex-local repair-launcher
```

普通 `codex` 启动仍不会自动更新脚本、刷新第三方模型目录或覆盖用户手写配置。

Android 不支持普通覆盖安装降级；从 2.4.1 回到更低 `versionCode` 需要发布更高 `versionCode` 的前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
