# Codex CLI 中文版 Android ARM64 一键安装包

这个目录发布 Codex CLI `0.142.4` 中文版的 ARM64 musl 构建：

- 目标：`aarch64-unknown-linux-musl`
- 适用：Android/Termux ARM64 或兼容的 ARM64 Linux musl 环境
- 说明：这不是 Android NDK/Bionic 目标；Code Mode 运行时在该 musl 构建中被禁用

## Termux 裸环境安装

如果是刚装好的 Termux，不能直接运行 `curl | sh`，因为裸环境里可能还没有 `curl`。先用 Termux 自带的 `pkg` 装下载器和证书：

```sh
pkg update -y && pkg install -y ca-certificates curl && curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

## 已有 curl 或 wget 的环境

如果当前环境已经有 `curl`：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

如果只有 `wget`：

```sh
wget -O- https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

真正没有 `pkg`、`curl`、`wget` 的 Android shell 不能远程一键安装；需要先手动提供下载器，或把 `install.sh` 和压缩包复制到设备上再本地执行。

脚本会：

- 安装常用依赖：`curl`、`tar`、`git`、`openssh`、`ripgrep`、`jq` 等
- 下载本目录的 `codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz`
- 校验压缩包和二进制 SHA256
- 安装到 `$PREFIX/bin/codex-zh`，并把 `codex` 指向它
- 运行 `codex --version` 做安装后检查

## 可选环境变量

```sh
CODEX_ZH_SKIP_DEPS=1 sh install.sh
CODEX_ZH_SKIP_RUN=1 sh install.sh
CODEX_ZH_INSTALL_NAME=codex-zh sh install.sh
CODEX_ZH_INSTALL_DIR="$HOME/.local/bin" sh install.sh
```

## 文件校验

```text
7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29  codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz
40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423  codex-0.142.4-zh-aarch64-unknown-linux-musl
```

## 手动安装

```sh
curl -fL -o codex.tgz https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz
tar -xzf codex.tgz
chmod +x codex-0.142.4-zh-aarch64-unknown-linux-musl
mkdir -p "$HOME/.local/bin"
mv codex-0.142.4-zh-aarch64-unknown-linux-musl "$HOME/.local/bin/codex-zh"
ln -sf "$HOME/.local/bin/codex-zh" "$HOME/.local/bin/codex"
codex --version
```

## 免责声明

这是社区汉化构建，不是 OpenAI 官方发行包。安装前请确认你信任本仓库和对应 SHA256。
