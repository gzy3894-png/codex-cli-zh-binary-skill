#!/usr/bin/env sh
set -u

info() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
[ -n "${PREFIX:-}" ] || export PREFIX="/data/data/com.gzy3894.codexfortui/files"
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/sbin:${PREFIX}/local/bin:${PATH:-}"

BOOT_DIR="$HOME/.codex-for-tui"
mkdir -p "$BOOT_DIR" "$HOME/.cache/codex-zh" 2>/dev/null || true
CONSENT_FILE="$BOOT_DIR/install-consent"

tty_read() {
  prompt="$1"
  default="${2:-}"
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
    else
      printf '%s: ' "$prompt" > /dev/tty
    fi
    IFS= read -r ans < /dev/tty || ans=""
  else
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default"
    else
      printf '%s: ' "$prompt"
    fi
    IFS= read -r ans || ans=""
  fi
  [ -n "$ans" ] || ans="$default"
  printf '%s' "$ans"
}

confirm_first_install() {
  [ -s "$CONSENT_FILE" ] && return 0

  cat >&2 <<'EOF'
检测到当前 Alpine 里还没有 codex，将进入首次安装。

将下载/安装的内容：
- Alpine 基础依赖：curl/wget/tar/gzip/jq/git/openssh/ripgrep/bash/coreutils 等。
- Codex 中文版 ARM64 二进制压缩包：约 70-90 MB，解压后二进制约 198 MB。
- 可选完整依赖模式还会安装 python3/nodejs/npm/gcc/cmake 等，下载体积可能 300-600 MB，安装后可能超过 1 GB。

网络说明：
- Alpine 依赖会优先尝试清华/北外/官方镜像，通常不一定需要代理。
- Codex 二进制来自 GitHub raw；网络不稳或 GitHub 访问慢时，建议准备代理/梯子。
- 后续下载支持断点续传和重试；失败后重新打开 App 会继续本地流程。
EOF

  while :; do
    printf '%s\n' "请选择：" >&2
    printf '%s\n' "1. 继续安装" >&2
    printf '%s\n' "2. 退出到 shell，不安装" >&2
    printf '%s\n' "3. 本次跳过自动启动" >&2
    choice="$(tty_read "请输入选项编号" "1")"
    case "$choice" in
      1|"")
        date '+%Y-%m-%d %H:%M:%S' > "$CONSENT_FILE" 2>/dev/null || true
        return 0
        ;;
      2)
        info "已退出安装。以后输入 codex 或重新打开 App 可继续。"
        exit 0
        ;;
      3)
        info "本次跳过自动启动。"
        exit 0
        ;;
      *) warn "请输入 1、2 或 3。" ;;
    esac
  done
}

if [ "${CODEX_FOR_TUI_AUTO_START:-1}" = "0" ]; then
  info "已跳过 Codex 自动启动，因为 CODEX_FOR_TUI_AUTO_START=0"
  exit 0
fi

if have codex; then
  info "Codex 已安装，正在启动..."
  codex
  exit $?
fi

if [ -x "$HOME/.local/bin/codex-local-resume" ]; then
  info "检测到未完成的 Codex 本地配置，继续恢复..."
  CODEX_ZH_SKIP_RUN=0 "$HOME/.local/bin/codex-local-resume"
  exit $?
fi

if [ -x "/usr/local/bin/codex-local-resume" ]; then
  info "检测到未完成的 Codex 本地配置，继续恢复..."
  CODEX_ZH_SKIP_RUN=0 "/usr/local/bin/codex-local-resume"
  exit $?
fi

confirm_first_install

installer="${PREFIX}/local/bin/install-reterminal-alpine.sh"
if [ ! -s "$installer" ]; then
  installer="$BOOT_DIR/install-reterminal-alpine.sh"
  url="${CODEX_ZH_INSTALLER_URL:-https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh}"
  info "未找到内置安装器，尝试下载：$url"
  if have curl; then
    curl -fL --http1.1 --retry 5 --retry-delay 2 --retry-all-errors -C - -o "$installer.part" "$url" && mv "$installer.part" "$installer"
  elif have wget; then
    wget -c -O "$installer.part" "$url" && mv "$installer.part" "$installer"
  else
    warn "缺少 curl/wget，且没有内置安装器。请先安装网络下载工具后重试。"
    exit 1
  fi
  chmod 755 "$installer" 2>/dev/null || true
fi

info "首次启动 Codex for TUI，开始一键安装 Codex..."
info "安装过程支持断点续传；如果网络失败，退出后重新打开 App 会继续。"
CODEX_ZH_SKIP_RUN=0 sh "$installer"
