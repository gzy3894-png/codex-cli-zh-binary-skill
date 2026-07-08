# Codex CLI 中文版 Android ARM64 安装包

这个目录发布 Codex CLI `0.142.4` 中文版的 ARM64 musl 构建和 Android/Alpine 安装脚本。

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

Codex for TUI 2.3.1 用户建议覆盖安装最新 APK；2.3.1 新增 `codex-doctor`、`codex-clean`、`codex-ops`，用于只读诊断、可回滚清理、运维日志和断线续连提示。2.3.0 的稳定化回归、2.2.9 的后台/折叠 WebView 截图修复、2.2.6 的 bridge 并发请求修复、2.2.5 的 RTK hook 绝对路径修复和 2.2.3 的后台 bridge 消费修复继续保留，普通启动规则不变。已经完成首次安装但只需要更新脚本时，可以手动运行：

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

如果菜单里出现 `1. 新建配置 / 2. 选择配置 / 3. 编辑当前配置 / 8. 修复全权限授权`，说明脚本已经更新到包含配置菜单和授权持久化修复的版本。需要修复授权时选择第 8 项；它会写入 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`。

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

它只刷新 `model_catalog_json` 指向的 JSON 文件，并保留当前 `model` 和 `model_reasoning_effort`。

新建、编辑、切换或保存第三方 API 配置时运行：

```sh
codex 配置模式
```

该命令会打开配置管理器，支持新建配置、选择配置、编辑当前配置、查看配置、删除配置、保存当前配置、刷新模型目录和修复全权限授权。第三方配置会写入 `config.toml`、`auth.json` 和 `model_catalog_json`；内部 provider id 保持 `custom`，provider 名称写为 `OpenAI`，`base_url` 可指向兼容 OpenAI Responses API 的第三方服务。新建或编辑完成后会主动询问是否保存为配置档，切换或退出前会提示保存未保存修改。配置切换会保持自动压缩、fast mode、goals、statusline、RTK hook、context hook 和全权限设置；全权限模式会同时写入 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`。

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
model_auto_compact_token_limit = 220000
service_tier = "default"
model_catalog_json = "/root/.codex/model_catalog.json"
disable_response_storage = true

[features]
auto_compaction = true
fast_mode = true
goals = true
hooks = true

[tui]
status_line = ["model-with-reasoning", "current-dir", "context-remaining", "used-tokens", "total-input-tokens", "total-output-tokens", "fast-mode", "task-progress"]
status_line_use_colors = true

[model_providers.custom]
name = "custom"
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

`/model` 菜单的模型目录来自 `model_catalog_json`。后续服务端模型变化时，手动执行：

```sh
codex-local refresh-models
```

需要重新进入第三方配置引导时，推荐执行：

```sh
codex 配置模式
```

该命令会进入配置菜单；选择新建/编辑时会重新请求 `/models` 并让你选择默认模型，但保留自动压缩、fast mode、goals、statusline 等通用配置。

## 本地维护命令

```sh
codex 更新
codex 配置模式
codex-local status
codex-local doctor
codex-local configure
codex-local refresh-models
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
codex-context verify
```

普通用户不需要再进入 Codex TUI 运行 `/hooks`。快捷授权会清理 `~/.codex/config.toml` 里的旧 Codex for TUI 用户级 hook 块；用户自己的 hooks 不会被授权或删除。检查 RTK/context 命令：

```sh
codex-rtk status
codex-rtk disable
codex-context status
codex-context disable
```

## 文件校验

```text
7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29  codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz
40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423  codex-0.142.4-zh-aarch64-unknown-linux-musl
F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259  alpine-minirootfs-3.24.1-aarch64.tar.gz
```

## 免责声明

这是社区汉化构建，不是 OpenAI 官方发行包。安装前请确认你信任本仓库、Release 资产和对应 SHA256。
