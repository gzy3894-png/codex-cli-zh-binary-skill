# shellcheck shell=sh
[ "${CODEX_ZH_COMMON_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_COMMON_LOADED=1

: "${CODEX_ZH_VERSION:=0.142.4}"
: "${CODEX_ZH_TARGET:=aarch64-unknown-linux-musl}"
: "${CODEX_ZH_BRANCH:=android-arm64-musl-installer}"
: "${CODEX_ZH_REPO_RAW:=https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
: "${CODEX_ZH_SCRIPT_BASE_URL:=$CODEX_ZH_REPO_RAW/$CODEX_ZH_BRANCH/android-arm64-musl}"
: "${CODEX_ZH_SCRIPT_RELEASE_BASE_URL:=https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/latest/download}"
: "${CODEX_ZH_BINARY_BASE_URL:=https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/download/codex-for-tui-v1.0.0}"
: "${CODEX_ZH_INSTALL_NAME:=codex}"
: "${CODEX_ZH_PROVIDER_ID:=custom}"

CODEX_ZH_ARCHIVE="codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}.tar.gz"
CODEX_ZH_ARCHIVE_SHA256="${CODEX_ZH_ARCHIVE_SHA256:-7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29}"
CODEX_ZH_BIN_SHA256="${CODEX_ZH_BIN_SHA256:-40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423}"

codex_info() { printf '%s\n' "$*"; }
codex_warn() { printf '警告: %s\n' "$*" >&2; }
codex_die() { printf '错误: %s\n' "$*" >&2; exit 1; }
codex_have() { command -v "$1" >/dev/null 2>&1; }
codex_upper() { tr '[:lower:]' '[:upper:]'; }

codex_init_env() {
  [ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
  mkdir -p "$HOME" 2>/dev/null || true
  export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:${PREFIX:-}/local/bin:${PATH:-}"
}

codex_shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

codex_toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

codex_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

codex_home() {
  printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"
}

codex_state_root() {
  printf '%s\n' "${CODEX_ZH_STATE_ROOT:-$(codex_home)/install-state}"
}

codex_cache_root() {
  printf '%s\n' "${CODEX_ZH_CACHE_ROOT:-$HOME/.cache/codex-zh}"
}

codex_script_cache_root() {
  printf '%s\n' "${CODEX_ZH_SCRIPT_CACHE_ROOT:-$(codex_cache_root)/scripts}"
}

codex_share_dir() {
  printf '%s\n' "${CODEX_ZH_SHARE_DIR:-$HOME/.local/share/codex-zh}"
}

codex_script_install_root() {
  printf '%s\n' "${CODEX_ZH_SCRIPT_INSTALL_ROOT:-$(codex_share_dir)/scripts}"
}

codex_install_dir() {
  if [ -n "${CODEX_ZH_INSTALL_DIR:-}" ]; then
    printf '%s\n' "$CODEX_ZH_INSTALL_DIR"
  elif [ "$(id -u 2>/dev/null || printf 1)" = "0" ] && [ -w /usr/local/bin ]; then
    printf '%s\n' "/usr/local/bin"
  else
    printf '%s\n' "$HOME/.local/bin"
  fi
}

codex_real_bin_path() {
  printf '%s/%s\n' "$(codex_install_dir)" "codex-zh-bin"
}

codex_launcher_path() {
  printf '%s/%s\n' "$(codex_install_dir)" "$CODEX_ZH_INSTALL_NAME"
}

codex_ensure_private_dir() {
  mkdir -p "$1"
  chmod 700 "$1" 2>/dev/null || true
}

codex_sha256_file() {
  if codex_have sha256sum; then
    sha256sum "$1" | awk '{print $1}' | codex_upper
  elif codex_have openssl; then
    openssl dgst -sha256 "$1" | awk '{print $2}' | codex_upper
  else
    codex_die "缺少 sha256sum 或 openssl，无法校验文件"
  fi
}

codex_verify_sha256() {
  file="$1"
  expected="$(printf '%s' "$2" | codex_upper)"
  actual="$(codex_sha256_file "$file")"
  [ "$actual" = "$expected" ] || codex_die "SHA256 不匹配：$file，实际 $actual，期望 $expected"
}

codex_persist_path() {
  dir="$1"
  mkdir -p "$dir"
  for profile_file in "$HOME/.profile" "$HOME/.ashrc" "$HOME/.bashrc"; do
    [ -f "$profile_file" ] || : > "$profile_file" 2>/dev/null || continue
    grep -F "$dir" "$profile_file" >/dev/null 2>&1 && continue
    {
      printf '\n# codex-zh\n'
      printf 'case ":${PATH:-}:" in *":%s:"*) ;; *) export PATH="%s:${PATH:-}" ;; esac\n' "$dir" "$dir"
    } >> "$profile_file"
  done
  if [ "$(id -u 2>/dev/null || printf 1)" = "0" ] && [ -d /etc/profile.d ]; then
    {
      printf 'case ":${PATH:-}:" in\n'
      printf '  *":%s:"*) ;;\n' "$dir"
      printf '  *) export PATH="%s:${PATH:-}" ;;\n' "$dir"
      printf 'esac\n'
    } > /etc/profile.d/codex-zh.sh 2>/dev/null || true
    chmod 644 /etc/profile.d/codex-zh.sh 2>/dev/null || true
  fi
}

codex_install_case_variants() {
  dir="$1"
  target="$2"
  for c in c C; do for o in o O; do for d in d D; do for e in e E; do for x in x X; do
    link="$dir/$c$o$d$e$x"
    [ "$link" = "$target" ] && continue
    ln -sf "$target" "$link" 2>/dev/null || true
  done; done; done; done; done
}
