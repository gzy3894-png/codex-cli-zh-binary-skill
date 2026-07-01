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
