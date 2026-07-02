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

只有这些路径会拉取脚本：

1. 首次打开 APK 且本地没有 `codex`，用户确认安装后。
2. 用户显式运行：

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
- 生成默认 `AGENTS.md`。
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
model_auto_compact_token_limit = 120000
model_catalog_json = "/root/.codex/model_catalog.json"
disable_response_storage = true

[features]
auto_compaction = true
hooks = false

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

## 本地维护命令

```sh
codex-local status
codex-local doctor
codex-local configure
codex-local refresh-models
codex-local repair-launcher
codex-local run --version
codex-update check
codex-update apply
```

`codex-local configure` 会显式重写第三方 provider 配置；普通 `codex` 启动不会调用它。

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

本地 shell 脚本没有可靠的“接收远端推送”能力。自动拉取只能做轮询或启动时检查；这会造成隐藏联网和启动时改配置。当前设计改为显式命令：用户运行 `codex-update check/apply` 才检测和应用脚本更新。

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

**Codex 结束时报 `Stop hook exited with code 127`？**

脚本生成的新配置会写入：

```toml
[features]
hooks = false
```

如果你迁移了旧配置，请手动检查 `~/.codex/config.toml`。

## 文件校验

```text
7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29  codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz
40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423  codex-0.142.4-zh-aarch64-unknown-linux-musl
F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259  alpine-minirootfs-3.24.1-aarch64.tar.gz
```

## 免责声明

这是社区汉化构建，不是 OpenAI 官方发行包。安装前请确认你信任本仓库、Release 资产和对应 SHA256。
