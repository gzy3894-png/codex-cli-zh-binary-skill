# Codex CLI 中文版 Android ARM64 一键安装包

这个目录发布 Codex CLI `0.142.4` 中文版的 ARM64 musl 构建：

- 目标：`aarch64-unknown-linux-musl`
- 推荐环境：Android Termux + Alpine proot
- 备用环境：原生 Termux ARM64 或兼容 ARM64 Linux musl 环境
- 说明：这不是 Android NDK/Bionic 目标；Code Mode 运行时在该 musl 构建中被禁用

## 推荐：裸 Termux 一键安装

推荐使用 `install-alpine-proot.sh`。它会：

- 安装 Termux 侧依赖：`ca-certificates`、`curl`、`tar`、`gzip`、`proot`、`jq` 等
- 下载并校验 Alpine `3.24.1` aarch64 minirootfs
- 直接解压 rootfs，不依赖 `proot-distro install debian/ubuntu` 的 OCI registry 流程
- 把 Alpine apk 源切到 HTTP TUNA，失败时自动切 BFSU
- 在 Alpine 内安装 Codex 常用依赖
- 下载并校验 Codex CLI `0.142.4` 中文 ARM64 musl 二进制
- 开局询问第三方 API Base URL 和 API Key
- 自动补齐 API Base URL 的 `/v1` 后缀
- 请求 `/models`，让用户选择默认模型和启用模型
- 生成 `~/.codex/config.toml`，默认使用 `wire_api = "responses"`
- 设置 `[features] hooks = false`，避免迁移旧 hooks 后出现 `Stop hook exited with code 127`
- 安装 `codex` 和 `codex-alpine` 命令

刚装好的 Termux 执行这一条：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl && curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-alpine-proot.sh | sh
```

如果已经有 `curl`：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-alpine-proot.sh | sh
```

如果只想先安装文件、不配置 API：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-alpine-proot.sh | CODEX_ZH_SKIP_API_SETUP=1 sh
```

安装完成后运行：

```sh
codex
```

备用入口：

```sh
codex-alpine
```

## 开局 API 配置

安装器会要求输入：

1. API Base URL，例如 `https://api.example.com` 或 `https://api.example.com/v1`
2. API Key
3. 默认模型编号
4. 启用模型编号，多个用英文逗号分隔

Base URL 会自动规范化：

- `https://api.example.com` -> `https://api.example.com/v1`
- `https://api.example.com/` -> `https://api.example.com/v1`
- `https://api.example.com/v1` -> 保持不变

生成的配置使用环境变量读取密钥，不把 key 写进 `config.toml`：

```toml
model_provider = "custom"
model = "你选择的默认模型"
model_reasoning_effort = "medium"
model_auto_compact_token_limit = 120000

[features]
hooks = false

[model_providers.custom]
name = "custom"
base_url = "https://api.example.com/v1"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
```

密钥保存在 Alpine rootfs 的 `/root/.codex/env`，权限为 `600`。`codex` 启动器会进入 proot 前自动读取它。

## 为什么推荐 Alpine proot

实测原生 Termux 路线在部分设备和代理环境下可能出现：

- Codex 流式输出反复 `Reconnecting`
- `Stream disconnected before completion`
- GitHub raw 或 git clone 偶发 `SSL_read unexpected eof`
- `proot-distro install debian/ubuntu` 卡在 OCI registry 认证并报 `SSL: UNEXPECTED_EOF_WHILE_READING`
- Alpine 官方 CDN `apk update` 报 I/O error

Alpine proot 路线把 rootfs 下载、校验、解压和 apk mirror 都固定下来，能显著减少这些变量。

## 备用：原生 Termux 安装

原生安装脚本仍保留。如果你确认自己的 Termux 原生环境流式响应稳定，可以执行：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

轻量依赖模式：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | CODEX_ZH_DEPS_PROFILE=minimal sh
```

## 常见问题

**卡在 `bash.bashrc (Y/I/N/O/D/Z)` 怎么办？**

执行：

```sh
DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -f install -y
```

**`proot-distro install debian/ubuntu` 报 SSL EOF 怎么办？**

不用走这条路线。推荐脚本直接下载 Alpine rootfs tarball 并本地解压，不需要 Docker/OCI registry 认证。

**Alpine `apk update` 报 I/O error 怎么办？**

推荐脚本默认写入：

```text
http://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/main
http://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/community
```

失败时自动切到：

```text
http://mirrors.bfsu.edu.cn/alpine/v3.24/main
http://mirrors.bfsu.edu.cn/alpine/v3.24/community
```

**Codex 回复正常，但结束时报 `Stop hook exited with code 127` 怎么办？**

这是旧配置里的停止 hook 迁移到新环境后找不到命令。推荐脚本默认写入：

```toml
[features]
hooks = false
```

**`/sdcard` 权限不足怎么办？**

在 Termux 里执行：

```sh
termux-setup-storage
```

然后重新运行安装命令。安装器本身不强制依赖 `/sdcard`，但 launcher 会把 `/sdcard` 绑定进 Alpine，方便后续访问下载目录。

**代理下长连接不稳怎么办？**

Clash Meta / Mihomo 建议：

- Stack Mode 先用 `Mixed Stack`
- 关闭 IPv6 后测试
- API 域名固定到单个稳定节点，不要走自动测速组
- 若服务端支持，优先用 HTTP/1.1 测试 `/models` 和 `/responses`

测试：

```sh
curl -v --http1.1 https://api.example.com/v1/models
```

返回 `401 missing Authorization` 说明网络通了，只是没有带 key。

## 可选环境变量

```sh
CODEX_ZH_SKIP_API_SETUP=1 sh install-alpine-proot.sh
CODEX_ZH_SKIP_RUN=1 sh install-alpine-proot.sh
CODEX_ZH_PROVIDER_ID=omnimind sh install-alpine-proot.sh
CODEX_ZH_INSTALL_NAME=codex-zh sh install-alpine-proot.sh
CODEX_ZH_ALIAS_NAME=codex-alpine sh install-alpine-proot.sh
CODEX_ZH_ALPINE_URL=https://example.com/alpine-minirootfs.tar.gz sh install-alpine-proot.sh
CODEX_ZH_ALPINE_SHA256=... sh install-alpine-proot.sh
```

## 文件校验

```text
7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29  codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz
40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423  codex-0.142.4-zh-aarch64-unknown-linux-musl
F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259  alpine-minirootfs-3.24.1-aarch64.tar.gz
```

## 免责声明

这是社区汉化构建，不是 OpenAI 官方发行包。安装前请确认你信任本仓库和对应 SHA256。
