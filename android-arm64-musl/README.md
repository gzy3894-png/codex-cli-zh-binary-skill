# Codex CLI 中文版 Android ARM64 一键安装包

这个目录发布 Codex CLI `0.142.4` 中文版的 ARM64 musl 构建：

- 目标：`aarch64-unknown-linux-musl`
- 适用：Android/Termux ARM64 或兼容的 ARM64 Linux musl 环境
- 说明：这不是 Android NDK/Bionic 目标；Code Mode 运行时在该 musl 构建中被禁用

## Termux 裸环境一键安装

如果是刚装好的 Termux，不能直接运行 `curl | sh`，因为裸环境里可能还没有 `curl`。先安装下载器和证书，然后脚本会继续安装 Codex 运行和常见工作环境依赖。命令里的 dpkg 参数会自动保留已有配置文件，避免 `bash.bashrc` 这类英文提问卡住：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

默认 `full` 依赖包括：

- Codex 下载/运行：`ca-certificates`、`curl`、`wget`、`tar`、`gzip`、`unzip`、`xz-utils`
- 代码工作流：`git`、`openssh`、`ripgrep`、`fd`、`jq`
- 常用语言环境：`python`、`python-pip`、`nodejs`、`npm`
- Shell/文本/补丁工具：`bash`、`coreutils`、`findutils`、`sed`、`grep`、`gawk`、`diffutils`、`patch`
- 常见本地编译依赖：`make`、`clang`、`binutils`、`lld`、`pkg-config`、`cmake`、`ninja`、`openssl`、`libffi`、`perl`、`procps`、`termux-tools`

如果只想装 Codex 运行所需的轻量依赖，可以用：

```sh
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | CODEX_ZH_DEPS_PROFILE=minimal sh
```

如果上次已经卡在 `bash.bashrc (Y/I/N/O/D/Z)` 并失败，先修复 dpkg 状态：

```sh
DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -f install -y
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

- 安装 Codex 运行和常见工作环境依赖，默认包含 Python/Node.js/native build 工具
- 下载本目录的 `codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz`
- 校验压缩包和二进制 SHA256
- 安装到 `$PREFIX/bin/codex-zh`，并把 `codex` 指向它
- 运行 `codex --version` 做安装后检查

## 可选环境变量

```sh
CODEX_ZH_SKIP_DEPS=1 sh install.sh
CODEX_ZH_SKIP_RUN=1 sh install.sh
CODEX_ZH_DEPS_PROFILE=minimal sh install.sh
CODEX_ZH_CACHE_DIR="$HOME/.cache/codex-zh" sh install.sh
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
