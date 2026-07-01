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
REMOTE_INSTALLER="$REMOTE_DIR/install-reterminal-alpine.sh"
REMOTE_RESUME="$REMOTE_DIR/codex-local-resume.sh"
CONSENT_FILE="$BOOT_DIR/install-consent"
mkdir -p "$BOOT_DIR" "$REMOTE_DIR" "$HOME/.cache/codex-zh" 2>/dev/null || true

clear_screen() {
  printf '\033[H\033[2J' 2>/dev/null || true
}

tty_read() {
  prompt="$1"
  default="${2:-}"
  if [ "${CODEX_ZH_FORCE_STDIN:-0}" != "1" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
    else
      printf '%s: ' "$prompt" > /dev/tty
    fi
    IFS= read -r ans < /dev/tty || ans=""
  else
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" >&2
    else
      printf '%s: ' "$prompt" >&2
    fi
    IFS= read -r ans || ans=""
  fi
  [ -n "$ans" ] || ans="$default"
  printf '%s' "$ans"
}

confirm_first_install() {
  [ -s "$CONSENT_FILE" ] && return 0

  clear_screen
  cat >&2 <<'EOF'
Codex for TUI 首次安装

将准备这些资源：
- Alpine 基础依赖
- Codex 中文版 ARM64 压缩包
- 最新安装/配置脚本
- 可选开发依赖

预计下载总量：
- Minimal：约 150-250 MB
- Full：约 400-700 MB

网络提示：
- Alpine 镜像通常不一定需要代理。
- Codex 压缩包来自 GitHub Release，网络不稳时建议开启代理。
- App 会先拉取云端最新安装脚本；失败时会回退到本地缓存或给出手动命令。
- 下载失败后可重新打开 App 继续。
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

script_url_candidates() {
  name="$1"
  override="${2:-}"
  [ -n "$override" ] && printf '%s\n' "$override"
  printf '%s\n' "$SCRIPT_BASE_URL/$name"
  [ -n "$SCRIPT_RELEASE_BASE_URL" ] && printf '%s\n' "$SCRIPT_RELEASE_BASE_URL/$name"
}

best_downloader() {
  if have curl; then
    printf '%s\n' "curl"
  elif have wget; then
    printf '%s\n' "wget"
  elif have busybox && busybox wget --help >/dev/null 2>&1; then
    printf '%s\n' "busybox-wget"
  else
    return 1
  fi
}

ensure_fetch_tool() {
  if tool="$(best_downloader 2>/dev/null)"; then
    printf '%s\n' "$tool"
    return 0
  fi
  if have apk; then
    warn "当前没有 curl/wget，尝试补装最小下载工具..."
    apk add --no-cache ca-certificates curl >/dev/null 2>&1 || \
      apk add --no-cache ca-certificates wget >/dev/null 2>&1 || true
  fi
  best_downloader
}

fetch_with_tool() {
  tool="$1"
  url="$2"
  dest="$3"
  part="$dest.part"
  rm -f "$part"
  if [ "$tool" = "curl" ]; then
    curl -fL --http1.1 \
      --retry 5 --retry-delay 2 --retry-all-errors \
      --connect-timeout 20 --speed-time 30 --speed-limit 1024 \
      -o "$part" "$url"
  elif [ "$tool" = "wget" ]; then
    wget -O "$part" --tries=5 --timeout=30 "$url"
  else
    busybox wget -O "$part" "$url"
  fi
  mv "$part" "$dest"
}

refresh_remote_script() {
  label="$1"
  name="$2"
  override="${3:-}"
  dest="$4"
  if ! tool="$(ensure_fetch_tool 2>/dev/null)"; then
    warn "缺少下载工具，无法刷新${label}。"
    [ -s "$dest" ] && warn "将继续使用本地缓存的${label}。"
    [ -s "$dest" ]
    return
  fi

  old_ifs="$IFS"
  IFS='
'
  for url in $(script_url_candidates "$name" "$override"); do
    [ -n "$url" ] || continue
    info "尝试拉取最新${label}: $url"
    if fetch_with_tool "$tool" "$url" "$dest"; then
      chmod 755 "$dest" 2>/dev/null || true
      info "已刷新${label}。"
      IFS="$old_ifs"
      return 0
    fi
    warn "${label}拉取失败：$url"
    rm -f "$dest.part"
  done
  IFS="$old_ifs"

  if [ -s "$dest" ]; then
    warn "无法拉取最新${label}，继续使用本地缓存。"
    return 0
  fi
  return 1
}

sync_remote_resume_command() {
  [ -s "$REMOTE_RESUME" ] || return 0
  for target in "$HOME/.local/bin/codex-local-resume" "/usr/local/bin/codex-local-resume"; do
    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir" 2>/dev/null || continue
    cp "$REMOTE_RESUME" "$target" 2>/dev/null || continue
    chmod 755 "$target" 2>/dev/null || true
  done
}

has_resume_state() {
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  [ -d "$codex_home/install-state" ] && return 0
  [ -d "$codex_home/api-profiles" ] && return 0
  [ -s "$codex_home/config.toml" ] && return 0
  [ -s "$codex_home/auth.json" ] && return 0
  return 1
}

choose_resume_runner() {
  if [ -x "$REMOTE_RESUME" ]; then
    printf '%s\n' "$REMOTE_RESUME"
    return 0
  fi
  if [ -x "$HOME/.local/bin/codex-local-resume" ]; then
    printf '%s\n' "$HOME/.local/bin/codex-local-resume"
    return 0
  fi
  if [ -x "/usr/local/bin/codex-local-resume" ]; then
    printf '%s\n' "/usr/local/bin/codex-local-resume"
    return 0
  fi
  return 1
}

print_manual_fetch_help() {
  warn "未能拿到安装脚本，无法继续自动安装。"
  printf '\n%s\n' "可稍后重试，或在 Alpine shell 手动执行任一命令：" >&2
  printf '%s\n' "wget -O - $SCRIPT_BASE_URL/install-reterminal-alpine.sh | sh" >&2
  printf '%s\n' "curl -fsSL $SCRIPT_BASE_URL/install-reterminal-alpine.sh | sh" >&2
}

refresh_remote_scripts() {
  refresh_remote_script "安装脚本" "install-reterminal-alpine.sh" "${CODEX_ZH_INSTALLER_URL:-}" "$REMOTE_INSTALLER" || true
  refresh_remote_script "恢复脚本" "codex-local-resume.sh" "${CODEX_ZH_RESUME_URL:-}" "$REMOTE_RESUME" || true
  sync_remote_resume_command
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

refresh_remote_scripts

if has_resume_state && resume_runner="$(choose_resume_runner 2>/dev/null)"; then
  info "检测到未完成的 Codex 本地配置，继续恢复..."
  CODEX_ZH_SKIP_RUN=0 "$resume_runner"
  exit $?
fi

confirm_first_install

if [ ! -x "$REMOTE_INSTALLER" ]; then
  print_manual_fetch_help
  exit 1
fi

info "首次启动 Codex for TUI，开始一键安装 Codex..."
info "安装过程支持断点续传；如果网络失败，退出后重新打开 App 会继续。"
CODEX_ZH_SKIP_RUN=0 sh "$REMOTE_INSTALLER"
