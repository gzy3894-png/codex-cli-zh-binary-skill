# Codex CLI 中文版 Android ARM64 安装包

这个目录发布 Codex CLI `0.144.1` 中文版的 ARM64 musl 构建和 Android/Alpine 安装脚本。

- 目标：`aarch64-unknown-linux-musl`
- 推荐环境：Codex for TUI APK 内置 Alpine/proot，或 ReTerminal Alpine
- 备用环境：Termux + Alpine proot、原生 Termux ARM64
- 说明：这不是 Android NDK/Bionic 目标；Code Mode 运行时在该 musl 构建中被禁用

## 脚本分层

当前脚本按职责拆分，避免启动链路叠加隐藏更新：

- `lib/codex-zh-common.sh`：路径、校验、日志、基础工具函数。
- `lib/codex-zh-download.sh`：下载、候选 URL、SHA256 校验。
- `lib/codex-zh-config.sh`：显式配置、`auth.json`、`model_catalog_json`、`/models` 刷新。
- `lib/codex-zh-local.sh`：本地安装、launcher、APK/Alpine/Termux/proot 入口。
- `lib/codex-zh-update.sh`：显式脚本更新。
- `codex-for-tui-bootstrap.sh`：APK 薄启动器；已安装 `codex` 时只负责 `exec codex`。
- `codex-update.sh`：用户手动运行的脚本更新命令。
- `codex-local-resume.sh`：本地诊断、配置、模型刷新、启动器修复命令。

旧脚本备份目录已从仓库删除，历史仍保留在 Git 历史和已发布 Release 中。当前 TUI 安装/更新链路的失败记录见 `../docs/codex-for-tui-failure-log-2026-07-02.md`；后续发版前必须重新完成该文档列出的验证。

## 启动和更新规则

普通启动不会自动联网更新脚本，不会请求 `/models`，不会覆盖 `~/.codex/config.toml`。

Codex for TUI 2.4.5 APK 内置固定 `0.144.1-zh.1` 二进制、launcher、完整受管脚本和模型能力目录。已安装旧版的用户覆盖安装 APK 并打开 App 后，会在 Codex 启动前自动完成离线、事务型环境升级：根配置成为活动 V2 profile，旧配置独立保留，runtime/session/SQLite 按站点隔离，`/model` 直接显示完整普通模型页，推理等级与 `rust-v0.144.1` 一致。升级失败会回滚并阻止启动，下次打开自动重试；2.4.3 起清除 musl 上不可用的 `code_mode_only`；2.4.4 恢复文件托盘发送附言；2.4.5 默认进入 shell（`CODEX_FOR_TUI_AUTO_START=0`）、过滤 proot 噪声并以 `/root/workspace` 为 cwd。不需要手动运行更新、修复 launcher、配置模式或设置 `CODEX_HOME`。

只有在不更新 APK、明确只想热更新脚本时，才手动运行：

```sh
codex 更新
codex-local repair-launcher
```

更新后普通启动 `codex` 会在启动 Codex 前询问是否快捷授权 Codex for TUI 增强功能。选择 `1` 后脚本会写入系统级 `/etc/codex/requirements.toml`，把 RTK/context 注册为 Codex 托管 hooks，不需要再进入 `/hooks` 手动信任。

如果当前处于官方 Codex 登录模式且 `codex login status` 未通过，普通交互启动会提示设备码登录。也可以手动运行：

```sh
codex 官方登录
```

该入口会调用 `codex login --device-auth`，解析登录链接和一次性验证码，并创建 Codex for TUI 安全登录任务卡；用户点击“打开/重开”后再进入 Custom Tabs；用户完成后再用 `codex login status` 验证。脚本不会打印 token、Cookie 或 `~/.codex/auth.json` 内容。

验证方式：

```sh
codex 配置模式
```

如果菜单里出现 `1. 新建配置 / 2. 选择配置 / 3. 编辑配置 / 7. 上下文与压缩策略 / 8. 修复全权限授权`，说明脚本已经更新到配置档 V2。首次进入时会检测并迁移旧配置档，迁移前创建完整备份；需要时可运行 `codex-local rollback-v1` 回滚。

只有这些路径会拉取脚本：

1. 首次打开 APK 且本地没有 `codex`，用户确认安装后。
2. 用户显式运行：

```sh
codex 更新
```

`codex 更新` 只增量更新脚本模块，不重装依赖，不替换 Codex 二进制，不覆盖通用配置。底层维护入口仍可直接使用：

```sh
codex-update check
codex-update apply
```

或者直接调用 bootstrap 的兼容入口：

```sh
codex-for-tui-bootstrap --update-scripts
```

第三方模型目录刷新也是显式命令：

```sh
codex-local refresh-models
```

Provider `/models` 只提供可用模型 ID；配置引擎会与随包 OpenAI Codex 官方目录精确合并真实推理等级、上下文窗口和工具能力。未知模型不会模糊猜测，默认使用保守能力并支持显式映射。所有 `codex-auto-*` 辅助模型会保留但标记为隐藏，使 Codex 原生 `/model` 直接进入完整普通模型页；已有 profile 会在启动物化时做同样的纯本地规范化，不请求 `/models`。刷新会保留当前 `model` 和 `model_reasoning_effort`；如果当前选择不再受支持，会要求重新选择。

新建、编辑、切换或保存第三方 API 配置时运行：

```sh
codex 配置模式
```

该命令会打开事务型配置档 V2，支持新建、选择、编辑、查看、删除、刷新模型目录、上下文/压缩策略和修复全权限授权。配置档使用稳定 ID；编辑原配置不会触发同名新建，取消确认不会写入。第三方配置会保存 `config.toml`、`auth.json` 和 `model_catalog_json`；内部 provider id 保持 `custom`，provider 名称默认写为 `OpenAI`，`base_url` 可指向兼容 OpenAI Responses API 的第三方服务。TOML 注释、未知字段和通用设置会保留；外部手改配置或登录态变化后，切换或退出前可同步、另存或暂不保存。全权限模式会同时写入 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`。

## ReTerminal Alpine 安装

在 ReTerminal Alpine 或 APK 内 Alpine 环境里执行：

```sh
wget -O - https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh | sh
```

已有 `curl` 时：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh | sh
```

脚本会：

- 安装 Alpine 依赖。
- 下载并校验 Codex 中文版 ARM64 musl 压缩包。
- 写入真实二进制 `codex-zh-bin` 和薄 launcher `codex`。
- 生成大小写兼容入口，例如 `Codex`、`CODEX`。
- 安装 `codex-local`、`codex-local-resume`、`codex-update`。
- 不生成默认 `AGENTS.md`；需要项目规则时，请在 Codex 里运行 `/init` 后自行编辑。
- 如果已有 `~/.codex/config.toml`，默认保留，不覆盖。
- 如果选择第三方 Responses API，写入 `auth.json` 和 `config.toml`。

第三方 API 非交互配置：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh | CODEX_ZH_SETUP_MODE=third_party CODEX_ZH_API_BASE=https://api.example.com/v1 CODEX_ZH_API_KEY=你的key sh
```

跳过 API 配置：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh | CODEX_ZH_SKIP_API_SETUP=1 sh
```

安装后运行：

```sh
codex
```

## Termux + Alpine proot

刚装好的 Termux 执行：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl && curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-alpine-proot.sh | sh
```

已有 `curl` 时：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-alpine-proot.sh | sh
```

这个入口只负责 Termux/proot 层：

- 安装 Termux 侧依赖。
- 下载并校验 Alpine `3.24.1` aarch64 minirootfs。
- 解压 rootfs。
- 把当前脚本树复制进 rootfs。
- 在 rootfs 内复用 `install-reterminal-alpine.sh` 完成 Codex 安装。
- 创建 Termux 侧入口 `codex-alpine` 和 `codex`。

默认 rootfs：

```text
$PREFIX/var/lib/codex-zh/codex-alpine/rootfs
```

默认入口：

```sh
codex-alpine
codex
```

## 原生 Termux 安装

原生 Termux 不是首选路线，但保留安装入口：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

## 第三方 API 配置

第三方 Responses API 配置需要：

1. API Base URL，例如 `https://api.example.com` 或 `https://api.example.com/v1`
2. API Key
3. 默认模型编号

Base URL 会自动规范化：

- `https://api.example.com` -> `https://api.example.com/v1`
- `https://api.example.com/` -> `https://api.example.com/v1`
- `https://api.example.com/v1` -> 保持不变

密钥写入 `~/.codex/auth.json`，不写进 `config.toml`。第三方 provider 通过 command auth 读取 token。

生成配置示例：

```toml
model_provider = "custom"
model = "你选择的默认模型"
model_reasoning_effort = "medium"
model_catalog_json = "/root/.codex/model_catalog.json"
approval_policy = "never"
sandbox_mode = "danger-full-access"

[features]
hooks = true

[model_providers.custom]
name = "OpenAI"
base_url = "https://api.example.com/v1"
wire_api = "responses"
requires_openai_auth = false

[model_providers.custom.auth]
command = "/root/.codex/bin/provider-api-key"
args = []
timeout_ms = 5000
refresh_interval_ms = 300000
cwd = "/root/.codex"
```

配置引擎只管理当前配置档拥有的 model/provider 字段，用户已有的 `[features]`、`[tui]`、MCP、hooks、注释和其他未知字段会保留。默认压缩策略为 `follow-model`，不会硬写固定 `model_auto_compact_token_limit`；只有用户选择固定策略时才写入该字段。

`/model` 菜单的模型目录来自 `model_catalog_json`；其中 `codex-auto-*` 辅助模型会隐藏，不占用首层 auto 快捷页。后续服务端模型变化时，手动执行：

```sh
codex-local refresh-models
```

需要重新进入第三方配置引导时，推荐执行：

```sh
codex 配置模式
```

该命令会进入配置菜单；选择新建/编辑时会重新请求 `/models`，再按官方能力目录展示模型和推理等级，同时保留用户通用配置。

## 本地维护命令

```sh
codex 更新
codex 配置模式
codex-local status
codex-local doctor
codex-local configure
codex-local refresh-models
codex-local profile-list
codex-local profile-show <名称或ID>
codex-local profile-use <名称或ID>
codex-local profile-rename <名称或ID> <新名称>
codex-local profile-delete <名称或ID>
codex-local profile-sync <名称或ID>
codex-local compact-policy [show|follow-model|fixed TOKENS]
codex-local config-status
codex-local rollback-v1
codex-local repair-launcher
codex-local run --version
codex-update check
codex-update apply
```

`codex 配置模式` 是推荐的第三方配置入口；`codex-local configure` 是兼容维护入口，使用同一套菜单。普通 `codex` 启动不会调用它们。

## AGENTS.md

安装器不再创建、复制或覆盖 `AGENTS.md`。如果需要项目级规则，请进入目标工作目录后在 Codex 里运行 `/init`，再编辑该目录下的 `AGENTS.md`。`codex 更新`、`codex 配置模式` 和普通启动都不应该改动用户自己的 AGENTS 文件。

## 可选环境变量

```sh
CODEX_ZH_SKIP_API_SETUP=1 sh install-reterminal-alpine.sh
CODEX_ZH_SKIP_RUN=1 sh install-reterminal-alpine.sh
CODEX_ZH_DEPS_PROFILE=minimal sh install-reterminal-alpine.sh
CODEX_ZH_TERMUX_DEPS_PROFILE=minimal sh install-alpine-proot.sh
CODEX_ZH_PROVIDER_ID=custom sh install-reterminal-alpine.sh
CODEX_ZH_INSTALL_NAME=codex-zh sh install-reterminal-alpine.sh
CODEX_ZH_OVERWRITE_CONFIG=1 sh install-reterminal-alpine.sh
CODEX_ZH_ALPINE_ROOT_BASE=$PREFIX/var/lib/codex-zh/codex-alpine sh install-alpine-proot.sh
CODEX_ZH_ALPINE_URL=https://example.com/alpine-minirootfs.tar.gz sh install-alpine-proot.sh
CODEX_ZH_ALPINE_SHA256=... sh install-alpine-proot.sh
```

## 常见问题

**为什么不是上游推送后自动更新？**

本地 shell 脚本没有可靠的“接收远端推送”能力。自动拉取只能做轮询或启动时检查；这会造成隐藏联网和启动时改配置。当前设计改为显式命令：用户运行 `codex 更新` 才应用脚本更新；`codex-update check/apply` 作为底层维护入口保留。

**打开 App 后没有进入 Codex，而是回到 shell？**

运行：

```sh
codex-local doctor
```

如果启动器缺失：

```sh
codex-local repair-launcher
```

**第三方 API 配置失败？**

确认服务兼容 OpenAI Responses API，并测试：

```sh
curl -v --http1.1 https://api.example.com/v1/models
```

返回 `401` 通常说明网络通了但缺少 Authorization；连接失败通常是 Base URL、代理或服务端兼容性问题。
生成后的第三方 provider 示例：

```toml
[model_providers.custom]
name = "OpenAI"
base_url = "https://api.example.com/v1"
wire_api = "responses"
requires_openai_auth = false
```

**Codex 结束时报 `Stop hook exited with code 127`？**

2.0.8 起脚本生成的新配置会写入：

```toml
[features]
hooks = true
```

如果你迁移了旧配置，请手动检查 `~/.codex/config.toml`。需要检查 RTK 和上下文压缩监测时运行：

```sh
codex-rtk status
codex-rtk verify
codex-context status
codex-context report
codex-context verify
```

普通用户不需要再进入 Codex TUI 运行 `/hooks`。快捷授权只管理 Codex for TUI 的 RTK/context 托管 hook；必要时清理 `~/.codex/config.toml` 里的旧版兼容 hook 块，不遍历或改写 session/transcript 文件。检查 RTK/context 命令：

```sh
codex-rtk status
codex-rtk disable
codex-context status
codex-context report
codex-context disable
codex 上下文监测
```

## 文件校验

```text
1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61  codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz
0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767  codex-0.144.1-zh-aarch64-unknown-linux-musl
F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259  alpine-minirootfs-3.24.1-aarch64.tar.gz
```

## 免责声明

这是社区汉化构建，不是 OpenAI 官方发行包。安装前请确认你信任本仓库、Release 资产和对应 SHA256。
