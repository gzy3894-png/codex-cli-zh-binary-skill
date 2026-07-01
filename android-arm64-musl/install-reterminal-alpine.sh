#!/usr/bin/env sh
set -eu

[ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
BRANCH="${CODEX_ZH_BRANCH:-android-arm64-musl-installer}"
REPO_RAW="${CODEX_ZH_REPO_RAW:-https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
SCRIPT_BASE_URL="${CODEX_ZH_SCRIPT_BASE_URL:-$REPO_RAW/$BRANCH/android-arm64-musl}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || printf '.')"
CACHE_DIR="${CODEX_ZH_SCRIPT_CACHE_ROOT:-$HOME/.cache/codex-zh/scripts}"

mini_have() { command -v "$1" >/dev/null 2>&1; }
mini_fetch() {
  url="$1"
  dest="$2"
  mkdir -p "$(dirname "$dest")"
  part="$dest.part"
  rm -f "$part"
  if mini_have curl; then
    if ! curl -fL --http1.1 --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 300 -o "$part" "$url"; then
      rm -f "$part"
      exit 1
    fi
  elif mini_have wget; then
    if ! wget -O "$part" "$url"; then
      rm -f "$part"
      exit 1
    fi
  else
    printf '错误: 缺少 curl/wget，无法下载模块：%s\n' "$url" >&2
    exit 1
  fi
  [ -s "$part" ] || { rm -f "$part"; exit 1; }
  mv "$part" "$dest"
}

load_lib() {
  rel="lib/$1"
  if [ -r "$SCRIPT_DIR/$rel" ]; then
    # shellcheck disable=SC1090
    . "$SCRIPT_DIR/$rel"
    export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
    return
  fi
  [ -r "$CACHE_DIR/$rel" ] || mini_fetch "$SCRIPT_BASE_URL/$rel" "$CACHE_DIR/$rel"
  # shellcheck disable=SC1090
  . "$CACHE_DIR/$rel"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$CACHE_DIR"
}

cache_support_script() {
  name="$1"
  [ -r "$SCRIPT_DIR/$name" ] && return 0
  [ -r "$CACHE_DIR/$name" ] || mini_fetch "$SCRIPT_BASE_URL/$name" "$CACHE_DIR/$name"
  chmod 755 "$CACHE_DIR/$name" 2>/dev/null || true
}

load_lib codex-zh-common.sh
load_lib codex-zh-download.sh
load_lib codex-zh-config.sh
load_lib codex-zh-local.sh
cache_support_script codex-local-resume.sh
cache_support_script codex-update.sh
cache_support_script codex-for-tui-bootstrap.sh
cache_support_script install-reterminal-alpine.sh
cache_support_script install-alpine-proot.sh
cache_support_script install.sh

codex_local_install_reterminal "$@"
