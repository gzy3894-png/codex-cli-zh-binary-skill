#!/usr/bin/env sh
set -eu

BRANCH="${CODEX_ZH_BRANCH:-android-arm64-musl-installer}"
REPO_RAW="${CODEX_ZH_REPO_RAW:-https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
SCRIPT_BASE_URL="${CODEX_ZH_SCRIPT_BASE_URL:-$REPO_RAW/$BRANCH/android-arm64-musl}"
SCRIPT_RELEASE_BASE_URL="${CODEX_ZH_SCRIPT_RELEASE_BASE_URL:-https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/latest/download}"

info() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
[ -n "${PREFIX:-}" ] || export PREFIX="/data/data/com.gzy3894.codexfortui/files"
export PATH="$HOME/.local/bin:/bin:/sbin:/usr/local/bin:/usr/bin:/usr/sbin:${PREFIX}/local/bin:${PATH:-}"

BOOT_DIR="$HOME/.codex-for-tui"
REMOTE_DIR="$BOOT_DIR/remote"
CONSENT_FILE="$BOOT_DIR/install-consent"
REMOTE_INSTALLER="$REMOTE_DIR/install-reterminal-alpine.sh"
mkdir -p "$BOOT_DIR" "$REMOTE_DIR" "$HOME/.local/bin" "$HOME/.cache/codex-zh" 2>/dev/null || true

tty_read() {
  prompt="$1"
  default="${2:-}"
  if [ "${CODEX_ZH_FORCE_STDIN:-0}" != "1" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    [ -n "$default" ] && printf '%s [%s]: ' "$prompt" "$default" > /dev/tty || printf '%s: ' "$prompt" > /dev/tty
    IFS= read -r ans < /dev/tty || ans=""
  else
    [ -n "$default" ] && printf '%s [%s]: ' "$prompt" "$default" >&2 || printf '%s: ' "$prompt" >&2
    IFS= read -r ans || ans=""
  fi
  [ -n "$ans" ] || ans="$default"
  printf '%s' "$ans"
}

confirm_first_install() {
  [ -s "$CONSENT_FILE" ] && return 0
  printf '\033[H\033[2J' 2>/dev/null || true
  cat >&2 <<'EOF'
Codex for TUI 首次安装

首次安装会下载依赖、Codex 中文版 ARM64 musl 二进制和安装脚本。
安装完成后的普通启动不会自动联网更新脚本，也不会刷新模型或覆盖配置。

请选择：
1. 继续安装
2. 退出到 shell，不安装
3. 本次跳过自动启动
EOF
  while :; do
    choice="$(tty_read "请输入选项编号" "1")"
    case "$choice" in
      1|"")
        date '+%Y-%m-%d %H:%M:%S' > "$CONSENT_FILE" 2>/dev/null || true
        return 0
        ;;
      2)
        info "已退出安装。以后重新打开 App 或运行安装命令可继续。"
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

best_downloader() {
  if have curl; then printf '%s\n' curl
  elif have wget; then printf '%s\n' wget
  elif have busybox && busybox wget --help >/dev/null 2>&1; then printf '%s\n' busybox-wget
  else return 1
  fi
}

fetch_atomic() {
  fa_url="$1"
  fa_dest="$2"
  fa_tool="$(best_downloader)" || return 1
  fa_part="$fa_dest.part"
  mkdir -p "$(dirname "$fa_dest")"
  rm -f "$fa_part"
  if [ "$fa_tool" = "curl" ]; then
    if ! curl -fL --http1.1 --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 300 -o "$fa_part" "$fa_url"; then
      rm -f "$fa_part"
      return 1
    fi
  elif [ "$fa_tool" = "wget" ]; then
    if ! wget -O "$fa_part" --tries=5 --timeout=30 "$fa_url"; then
      rm -f "$fa_part"
      return 1
    fi
  else
    if ! busybox wget -O "$fa_part" "$fa_url"; then
      rm -f "$fa_part"
      return 1
    fi
  fi
  [ -s "$fa_part" ] || { rm -f "$fa_part"; return 1; }
  mv "$fa_part" "$fa_dest"
}

script_urls() {
  name="$1"
  override="${2:-}"
  [ -n "$override" ] && printf '%s\n' "$override"
  printf '%s\n' "$SCRIPT_BASE_URL/$name"
  [ -n "$SCRIPT_RELEASE_BASE_URL" ] && printf '%s\n' "$SCRIPT_RELEASE_BASE_URL/$name"
}

refresh_one() {
  ro_label="$1"
  ro_name="$2"
  ro_override="${3:-}"
  ro_dest="$REMOTE_DIR/$ro_name"
  ro_tmp="$ro_dest.tmp"
  ro_old_ifs="$IFS"
  IFS='
'
  for ro_url in $(script_urls "$ro_name" "$ro_override"); do
    [ -n "$ro_url" ] || continue
    info "检测更新：$ro_label $ro_url"
    if fetch_atomic "$ro_url" "$ro_tmp"; then
      if [ -s "$ro_dest" ] && cmp -s "$ro_tmp" "$ro_dest"; then
        info "未变化：$ro_name"
        rm -f "$ro_tmp"
      else
        mv "$ro_tmp" "$ro_dest"
        chmod 755 "$ro_dest" 2>/dev/null || true
        info "已更新：$ro_name"
      fi
      IFS="$ro_old_ifs"
      return 0
    fi
    warn "下载失败：$ro_url"
    rm -f "$ro_tmp" "$ro_tmp.part"
  done
  IFS="$ro_old_ifs"
  [ -s "$ro_dest" ]
}

refresh_remote_scripts() {
  refresh_one "安装脚本" "install-reterminal-alpine.sh" "${CODEX_ZH_INSTALLER_URL:-}" || true
  refresh_one "本地命令" "codex-local-resume.sh" "${CODEX_ZH_RESUME_URL:-}" || true
  refresh_one "更新命令" "codex-update.sh" "${CODEX_ZH_UPDATE_URL:-}" || true
  refresh_one "bootstrap" "codex-for-tui-bootstrap.sh" "${CODEX_ZH_BOOTSTRAP_URL:-}" || true
  for lib in codex-zh-common.sh codex-zh-download.sh codex-zh-config.sh codex-zh-local.sh codex-zh-update.sh; do
    refresh_one "模块" "lib/$lib" "" || true
  done
  [ -s "$REMOTE_DIR/codex-local-resume.sh" ] && cp "$REMOTE_DIR/codex-local-resume.sh" "$HOME/.local/bin/codex-local-resume" 2>/dev/null && chmod 755 "$HOME/.local/bin/codex-local-resume" 2>/dev/null || true
  [ -s "$REMOTE_DIR/codex-local-resume.sh" ] && cp "$REMOTE_DIR/codex-local-resume.sh" "$HOME/.local/bin/codex-local" 2>/dev/null && chmod 755 "$HOME/.local/bin/codex-local" 2>/dev/null || true
  [ -s "$REMOTE_DIR/codex-update.sh" ] && cp "$REMOTE_DIR/codex-update.sh" "$HOME/.local/bin/codex-update" 2>/dev/null && chmod 755 "$HOME/.local/bin/codex-update" 2>/dev/null || true
}

has_local_state() {
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  [ -d "$codex_home/install-state" ] && return 0
  [ -s "$codex_home/config.toml" ] && return 0
  [ -s "$codex_home/auth.json" ] && return 0
  return 1
}

resume_runner() {
  for p in "$HOME/.local/bin/codex-local-resume" "$REMOTE_DIR/codex-local-resume.sh" "/usr/local/bin/codex-local-resume"; do
    [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

case "${1:-}" in
  --update-scripts|update)
    refresh_remote_scripts
    exit 0
    ;;
  --help|-h)
    printf '%s\n' "用法: codex-for-tui-bootstrap.sh [--update-scripts]" >&2
    exit 0
    ;;
esac

if [ "${CODEX_FOR_TUI_AUTO_START:-1}" = "0" ]; then
  info "已跳过 Codex 自动启动，因为 CODEX_FOR_TUI_AUTO_START=0"
  exit 0
fi

if have codex; then
  info "Codex 已安装，直接启动。"
  exec codex
fi

if has_local_state && runner="$(resume_runner 2>/dev/null)"; then
  warn "检测到本地状态但 Codex 启动器缺失；进入本地诊断，不拉取远端更新。"
  "$runner" doctor || true
fi

confirm_first_install

if [ ! -x "$REMOTE_INSTALLER" ]; then
  refresh_remote_scripts
fi

if [ ! -x "$REMOTE_INSTALLER" ]; then
  warn "未能拿到安装脚本，无法继续自动安装。"
  printf '%s\n' "可手动执行：" >&2
  printf '%s\n' "wget -O - $SCRIPT_BASE_URL/install-reterminal-alpine.sh | sh" >&2
  printf '%s\n' "curl -fsSL $SCRIPT_BASE_URL/install-reterminal-alpine.sh | sh" >&2
  exit 1
fi

info "开始首次安装 Codex for TUI。"
CODEX_ZH_SKIP_RUN=0 sh "$REMOTE_INSTALLER"
