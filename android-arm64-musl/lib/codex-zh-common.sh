# shellcheck shell=sh
[ "${CODEX_ZH_COMMON_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_COMMON_LOADED=1

: "${CODEX_ZH_VERSION:=0.144.1}"
: "${CODEX_ZH_TARGET:=aarch64-unknown-linux-musl}"
: "${CODEX_ZH_BRANCH:=android-arm64-musl-installer}"
: "${CODEX_ZH_REPO_RAW:=https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
: "${CODEX_ZH_SCRIPT_BASE_URL:=$CODEX_ZH_REPO_RAW/$CODEX_ZH_BRANCH/android-arm64-musl}"
: "${CODEX_ZH_SCRIPT_RELEASE_BASE_URL:=https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/latest/download}"
: "${CODEX_ZH_BINARY_BASE_URL:=https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/download/v0.144.1-zh.1}"
: "${CODEX_ZH_INSTALL_NAME:=codex}"
: "${CODEX_ZH_PROVIDER_ID:=custom}"
: "${CODEX_ZH_PROVIDER_NAME:=OpenAI}"
: "${CODEX_ZH_RUNTIME_EPOCH:=apk-2.5.16}"

CODEX_ZH_ARCHIVE="codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}.tar.gz"
CODEX_ZH_ARCHIVE_SHA256="${CODEX_ZH_ARCHIVE_SHA256:-1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61}"
CODEX_ZH_BIN_SHA256="${CODEX_ZH_BIN_SHA256:-0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767}"

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

codex_app_bridge_bin_dir() {
  if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX%/}/local/bin" ]; then
    printf '%s\n' "${PREFIX%/}/local/bin"
    return 0
  fi

  if [ -n "${PKG:-}" ]; then
    for prefix in "/data/user/0/$PKG" "/data/data/$PKG"; do
      [ -d "$prefix/local/bin" ] && { printf '%s\n' "$prefix/local/bin"; return 0; }
    done
  fi

  for prefix in \
    /data/user/0/com.gzy3894.codexfortui \
    /data/data/com.gzy3894.codexfortui \
    /data/user/0/com.gzy3894.codexfortui.test \
    /data/data/com.gzy3894.codexfortui.test \
    /data/user/0/com.gzy3894.codexfortui.debug \
    /data/data/com.gzy3894.codexfortui.debug
  do
    [ -d "$prefix/local/bin" ] && { printf '%s\n' "$prefix/local/bin"; return 0; }
  done

  return 1
}

codex_install_app_bridge_wrappers() {
  install_dir="$(codex_install_dir)"
  mkdir -p "$install_dir"
  for tool in codex-preview codex-push-image codex-push-media codex-browser codex-panel codex-session codex-rtk codex-context codex-doctor codex-clean codex-ops codex-dev-transfer; do
    wrapper="$install_dir/$tool"
    cat > "$wrapper" <<'EOF'
#!/usr/bin/env sh
set -eu

find_bridge_bin_dir() {
  if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX%/}/local/bin" ]; then
    printf '%s\n' "${PREFIX%/}/local/bin"
    return 0
  fi

  if [ -n "${PKG:-}" ]; then
    for prefix in "/data/user/0/$PKG" "/data/data/$PKG"; do
      [ -d "$prefix/local/bin" ] && { printf '%s\n' "$prefix/local/bin"; return 0; }
    done
  fi

  for prefix in \
    /data/user/0/com.gzy3894.codexfortui \
    /data/data/com.gzy3894.codexfortui \
    /data/user/0/com.gzy3894.codexfortui.test \
    /data/data/com.gzy3894.codexfortui.test \
    /data/user/0/com.gzy3894.codexfortui.debug \
    /data/data/com.gzy3894.codexfortui.debug
  do
    [ -d "$prefix/local/bin" ] && { printf '%s\n' "$prefix/local/bin"; return 0; }
  done

  return 1
}

tool="$(basename "$0")"
bridge_bin="$(find_bridge_bin_dir)" || {
  printf '找不到 Codex for TUI 桥接命令目录，请在 App 终端内运行: %s\n' "$tool" >&2
  exit 1
}
target="$bridge_bin/$tool"
[ -x "$target" ] || {
  printf '桥接命令不可执行: %s\n' "$target" >&2
  exit 1
}
export PREFIX="$(dirname "$(dirname "$bridge_bin")")"
exec "$target" "$@"
EOF
    chmod 755 "$wrapper" 2>/dev/null || true
  done
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

codex_config_engine_asset_list() {
  cat <<'EOF'
libexec/codex-config-engine.py
libexec/codex-session-defaults.py
libexec/codex-workspace-migrate.py
libexec/codex-runtime-session-import.py
data/openai-models.json
data/openai-models-source.json
vendor/python/tomlkit/__init__.py
vendor/python/tomlkit/_compat.py
vendor/python/tomlkit/_types.py
vendor/python/tomlkit/_utils.py
vendor/python/tomlkit/api.py
vendor/python/tomlkit/container.py
vendor/python/tomlkit/exceptions.py
vendor/python/tomlkit/items.py
vendor/python/tomlkit/parser.py
vendor/python/tomlkit/source.py
vendor/python/tomlkit/toml_char.py
vendor/python/tomlkit/toml_document.py
vendor/python/tomlkit/toml_file.py
vendor/python/tomlkit-0.13.2.dist-info/LICENSE
vendor/python/tomlkit-0.13.2.dist-info/METADATA
EOF
}

codex_support_file_list() {
  cat <<'EOF'
codex-apk-upgrade.sh
codex-for-tui-bootstrap.sh
codex-for-tui-self-test.sh
codex-local-resume.sh
codex-update.sh
install-reterminal-alpine.sh
install-alpine-proot.sh
install.sh
lib/codex-zh-common.sh
lib/codex-zh-download.sh
lib/codex-zh-config.sh
lib/codex-zh-local.sh
lib/codex-zh-update.sh
EOF
  codex_config_engine_asset_list
}

codex_support_file_mode() {
  case "$1" in
    *.sh|libexec/*.py) printf '%s\n' 755 ;;
    *) printf '%s\n' 644 ;;
  esac
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

codex_binary_file_fingerprint() {
  stat -c '%d:%i:%s:%Y' "$1" 2>/dev/null
}

codex_binary_build_cache_path() {
  printf '%s/binary-build-key-v1\n' "$(codex_state_root)"
}

codex_binary_cache_value() {
  cache_file="$1"
  cache_key="$2"
  sed -n "s/^${cache_key}=//p" "$cache_file" 2>/dev/null | sed -n '1p'
}

codex_binary_normalize_version() {
  printf '%s\n' "$1" |
    sed -n '1p' |
    cut -c1-48 |
    tr -c 'A-Za-z0-9._-' '_'
}

codex_binary_seed_build_cache() {
  binary="$1"
  version_raw="$2"
  verified_digest="$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')"
  epoch_raw="${4:-$CODEX_ZH_RUNTIME_EPOCH}"
  expected_digest="$(printf '%s' "$CODEX_ZH_BIN_SHA256" | tr '[:upper:]' '[:lower:]')"
  [ "${#verified_digest}" -eq 64 ] || return 1
  case "$verified_digest" in *[!0-9a-f]*) return 1 ;; esac
  [ "$verified_digest" = "$expected_digest" ] || return 1
  fingerprint="$(codex_binary_file_fingerprint "$binary")" || return 1
  version="$(codex_binary_normalize_version "$version_raw")"
  [ -n "$version" ] || version="codex"
  epoch="$(printf '%s' "$epoch_raw" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-32)"
  [ -n "$epoch" ] || epoch="runtime"
  digest_prefix="$(printf '%s' "$verified_digest" | cut -c1-16)"
  build_key="$version-$epoch-$digest_prefix"
  case "$build_key" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac

  cache_file="$(codex_binary_build_cache_path)"
  codex_ensure_private_dir "$(dirname "$cache_file")"
  cache_tmp="$cache_file.tmp.$$"
  (
    umask 077
    {
      printf 'schema=1\n'
      printf 'binary_path=%s\n' "$binary"
      printf 'fingerprint=%s\n' "$fingerprint"
      printf 'expected_sha256=%s\n' "$expected_digest"
      printf 'runtime_epoch=%s\n' "$epoch"
      printf 'version=%s\n' "$version"
      printf 'build_key=%s\n' "$build_key"
    } > "$cache_tmp"
  ) || {
    rm -f "$cache_tmp"
    return 1
  }
  chmod 600 "$cache_tmp" 2>/dev/null || true
  mv "$cache_tmp" "$cache_file" || {
    rm -f "$cache_tmp"
    return 1
  }
  printf '%s\n' "$build_key"
}

codex_binary_build_key() {
  binary="$1"
  epoch_raw="${2:-$CODEX_ZH_RUNTIME_EPOCH}"
  expected_digest="$(printf '%s' "$CODEX_ZH_BIN_SHA256" | tr '[:upper:]' '[:lower:]')"
  epoch="$(printf '%s' "$epoch_raw" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-32)"
  [ -n "$epoch" ] || epoch="runtime"
  fingerprint="$(codex_binary_file_fingerprint "$binary")" || return 1
  cache_file="$(codex_binary_build_cache_path)"
  if [ -r "$cache_file" ] &&
    [ "$(codex_binary_cache_value "$cache_file" schema)" = "1" ] &&
    [ "$(codex_binary_cache_value "$cache_file" binary_path)" = "$binary" ] &&
    [ "$(codex_binary_cache_value "$cache_file" fingerprint)" = "$fingerprint" ] &&
    [ "$(codex_binary_cache_value "$cache_file" expected_sha256)" = "$expected_digest" ] &&
    [ "$(codex_binary_cache_value "$cache_file" runtime_epoch)" = "$epoch" ]
  then
    cached_key="$(codex_binary_cache_value "$cache_file" build_key)"
    case "$cached_key" in
      ""|*[!A-Za-z0-9._-]*) ;;
      *) printf '%s\n' "$cached_key"; return 0 ;;
    esac
  fi

  actual_digest="$(codex_sha256_file "$binary" 2>/dev/null | tr '[:upper:]' '[:lower:]')" ||
    return 1
  [ "$actual_digest" = "$expected_digest" ] || return 1
  version_raw="$("$binary" --version 2>/dev/null | sed -n '1p')" || return 1
  [ -n "$version_raw" ] || version_raw="codex"
  codex_binary_seed_build_cache "$binary" "$version_raw" "$actual_digest" "$epoch"
}

codex_write_system_path_profile() {
  path_dir="$1"
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || return 0
  [ -d /etc/profile.d ] || return 0
  case "$path_dir" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$path_dir" in *'
'*) return 1 ;; esac
  {
    printf 'case ":${PATH:-}:" in\n'
    printf '  *":%s:"*) ;;\n' "$path_dir"
    printf '  *) export PATH="%s:${PATH:-}" ;;\n' "$path_dir"
    printf 'esac\n'
  } > /etc/profile.d/codex-zh.sh 2>/dev/null || return 1
  chmod 644 /etc/profile.d/codex-zh.sh 2>/dev/null || true
}

codex_persist_path() {
  path_dir="$1"
  [ "${CODEX_ZH_SKIP_PERSIST_PATH:-0}" != "1" ] || return 0
  mkdir -p "$path_dir"
  for profile_file in "$HOME/.profile" "$HOME/.ashrc" "$HOME/.bashrc"; do
    [ -f "$profile_file" ] || : > "$profile_file" 2>/dev/null || continue
    grep -F "$path_dir" "$profile_file" >/dev/null 2>&1 && continue
    {
      printf '\n# codex-zh\n'
      printf 'case ":${PATH:-}:" in *":%s:"*) ;; *) export PATH="%s:${PATH:-}" ;; esac\n' "$path_dir" "$path_dir"
    } >> "$profile_file"
  done
  codex_write_system_path_profile "$path_dir" || true
}

codex_install_case_variants() {
  dir="$1"
  target="$2"
  target_name="$(basename "$target")"
  for c in c C; do for o in o O; do for d in d D; do for e in e E; do for x in x X; do
    link="$dir/$c$o$d$e$x"
    [ "$link" = "$target" ] && continue
    ln -sf "$target_name" "$link" 2>/dev/null || true
  done; done; done; done; done
}
