#!/usr/bin/env sh
set -eu

VERSION="0.142.4"
TARGET="aarch64-unknown-linux-musl"
BRANCH="${CODEX_ZH_BRANCH:-android-arm64-musl-installer}"
REPO_RAW="${CODEX_ZH_REPO_RAW:-https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
BASE_URL="${CODEX_ZH_BASE_URL:-$REPO_RAW/$BRANCH/android-arm64-musl}"
ARCHIVE="codex-${VERSION}-zh-${TARGET}.tar.gz"
ARCHIVE_SHA256="7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29"
BIN_SHA256="40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423"

INSTALL_NAME="${CODEX_ZH_INSTALL_NAME:-codex}"
PROVIDER_ID="${CODEX_ZH_PROVIDER_ID:-custom}"
SKIP_API_SETUP="${CODEX_ZH_SKIP_API_SETUP:-0}"
SKIP_DEPS="${CODEX_ZH_SKIP_DEPS:-0}"
SKIP_RUN="${CODEX_ZH_SKIP_RUN:-0}"
DEPS_PROFILE="${CODEX_ZH_DEPS_PROFILE:-full}"

info() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
upper() { tr '[:lower:]' '[:upper:]'; }

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

sha256_file() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}' | upper
  elif have openssl; then
    openssl dgst -sha256 "$1" | awk '{print $2}' | upper
  else
    die "缺少 sha256sum 或 openssl"
  fi
}

download() {
  url="$1"
  dest="$2"
  if have curl; then
    curl -fL --http1.1 --retry 5 --retry-delay 2 --connect-timeout 20 -o "$dest" "$url"
  elif have wget; then
    wget -O "$dest" "$url"
  else
    die "缺少 curl 或 wget"
  fi
}

install_deps() {
  if [ "$SKIP_DEPS" = "1" ]; then
    warn "跳过依赖安装，因为 CODEX_ZH_SKIP_DEPS=1"
    return
  fi
  have apk || die "当前不是 Alpine 环境：找不到 apk。请切到 ReTerminal 的 Alpine 模式再运行。"

  info "安装 Alpine 依赖（$DEPS_PROFILE 模式）..."
  if [ "$(id -u)" = "0" ]; then
    apk update
    if [ "$DEPS_PROFILE" = "minimal" ]; then
      apk add --no-cache ca-certificates curl wget tar gzip jq git openssh-client ripgrep fd bash coreutils findutils sed grep gawk procps
    else
      apk add --no-cache \
        ca-certificates curl wget tar gzip unzip xz jq \
        git openssh-client ripgrep fd bash \
        coreutils findutils sed grep gawk diffutils patch procps \
        python3 py3-pip nodejs npm \
        make gcc g++ musl-dev pkgconf cmake ninja \
        openssl openssl-dev libffi-dev perl
    fi
  elif have sudo; then
    sudo apk update
    if [ "$DEPS_PROFILE" = "minimal" ]; then
      sudo apk add --no-cache ca-certificates curl wget tar gzip jq git openssh-client ripgrep fd bash coreutils findutils sed grep gawk procps
    else
      sudo apk add --no-cache \
        ca-certificates curl wget tar gzip unzip xz jq \
        git openssh-client ripgrep fd bash \
        coreutils findutils sed grep gawk diffutils patch procps \
        python3 py3-pip nodejs npm \
        make gcc g++ musl-dev pkgconf cmake ninja \
        openssl openssl-dev libffi-dev perl
    fi
  else
    die "apk 需要 root 或 sudo 权限。ReTerminal Alpine 通常默认是 root，请确认当前用户。"
  fi
}

tty_read() {
  prompt="$1"
  default="${2:-}"
  if [ -r /dev/tty ]; then
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

tty_read_secret() {
  prompt="$1"
  if [ -r /dev/tty ]; then
    printf '%s: ' "$prompt" > /dev/tty
    old_stty="$(stty -g < /dev/tty 2>/dev/null || true)"
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r ans < /dev/tty || ans=""
    [ -z "$old_stty" ] || stty "$old_stty" < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
  else
    printf '%s: ' "$prompt"
    IFS= read -r ans || ans=""
  fi
  printf '%s' "$ans"
}

normalize_api_base() {
  printf '%s' "$1" | sed 's/[[:space:]]//g; s#/*$##' | awk '
    /\/v1$/ { print; next }
    { print $0 "/v1" }
  '
}

parse_models() {
  json_file="$1"
  if have jq; then
    jq -r '.data[]?.id // empty' "$json_file" 2>/dev/null | sed '/^$/d'
  else
    sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json_file" | sed '/^$/d'
  fi
}

choose_model() {
  list_file="$1"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1
  info "可用模型："
  nl -w2 -s'. ' "$list_file" >&2
  choice="$(tty_read "请选择默认模型编号" "1")"
  case "$choice" in
    *[!0-9]*|"") choice=1 ;;
  esac
  if [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "$count" ] 2>/dev/null; then
    choice=1
  fi
  sed -n "${choice}p" "$list_file"
}

select_enabled_models() {
  list_file="$1"
  default_model="$2"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  picks="$(tty_read "启用哪些模型编号，逗号分隔；直接回车只启用默认模型" "")"
  if [ -z "$picks" ]; then
    printf '%s\n' "$default_model"
    return
  fi
  printf '%s' "$picks" | tr ',' '\n' | while IFS= read -r n; do
    n="$(printf '%s' "$n" | sed 's/[^0-9]//g')"
    [ -n "$n" ] || continue
    [ "$n" -ge 1 ] 2>/dev/null || continue
    [ "$n" -le "$count" ] 2>/dev/null || continue
    sed -n "${n}p" "$list_file"
  done | awk 'NF && !seen[$0]++'
}

write_codex_config() {
  api_base="$1"
  api_key="$2"
  default_model="$3"
  enabled_file="$4"

  codex_home="${CODEX_HOME:-$HOME/.codex}"
  mkdir -p "$codex_home"
  chmod 700 "$codex_home"

  env_file="$codex_home/env"
  {
    printf 'OPENAI_API_KEY='
    shell_quote "$api_key"
    printf '\n'
  } > "$env_file"
  chmod 600 "$env_file"

  config_file="$codex_home/config.toml"
  {
    printf 'model_provider = "%s"\n' "$PROVIDER_ID"
    printf 'model = "%s"\n' "$default_model"
    printf 'model_reasoning_effort = "medium"\n'
    printf 'model_auto_compact_token_limit = 120000\n'
    printf 'disable_response_storage = true\n'
    printf '\n[features]\n'
    printf 'hooks = false\n'
    printf '\n[model_providers.%s]\n' "$PROVIDER_ID"
    printf 'name = "%s"\n' "$PROVIDER_ID"
    printf 'base_url = "%s"\n' "$api_base"
    printf 'wire_api = "responses"\n'
    printf 'env_key = "OPENAI_API_KEY"\n'
    printf '\n[projects."%s"]\n' "$HOME"
    printf 'trust_level = "trusted"\n'
    printf '\n[tui]\n'
    printf 'status_line = ["model-with-reasoning", "current-dir", "context-remaining"]\n'
    printf 'status_line_use_colors = true\n'
    if [ -s "$enabled_file" ]; then
      while IFS= read -r model_name; do
        safe="$(printf '%s' "$model_name" | sed 's/[^A-Za-z0-9_.-]/-/g')"
        printf '\n[profiles.%s]\n' "$safe"
        printf 'model_provider = "%s"\n' "$PROVIDER_ID"
        printf 'model = "%s"\n' "$model_name"
      done < "$enabled_file"
    fi
  } > "$config_file"
  chmod 600 "$config_file"
}

create_launcher() {
  path="$1"
  binary="$2"
  binary_q="$(shell_quote "$binary")"
  cat > "$path" <<EOF
#!/usr/bin/env sh
env_file="\${CODEX_HOME:-\$HOME/.codex}/env"
if [ -r "\$env_file" ]; then
  . "\$env_file"
  export OPENAI_API_KEY
fi
export HOME="\${HOME:-/root}"
export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"
export PATH="\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:\${PATH:-}"
exec $binary_q "\$@"
EOF
  chmod 755 "$path"
}

case "$(uname -m 2>/dev/null || true)" in
  aarch64|arm64) ;;
  *) warn "这个安装器面向 Android ARM64；当前架构是 $(uname -m 2>/dev/null || echo unknown)" ;;
esac

[ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
mkdir -p "$HOME"

install_deps

cache_dir="${CODEX_ZH_CACHE_DIR:-$HOME/.cache/codex-zh}"
install_dir="${CODEX_ZH_INSTALL_DIR:-$HOME/.local/bin}"
tmp="${TMPDIR:-/tmp}/codex-zh-reterminal-alpine.$$"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$cache_dir" "$install_dir" "$tmp"

archive_path="$cache_dir/$ARCHIVE"
if [ -f "$archive_path" ] && [ "$(sha256_file "$archive_path")" != "$ARCHIVE_SHA256" ]; then
  warn "缓存压缩包校验失败，将重新下载"
  rm -f "$archive_path"
fi
if [ ! -f "$archive_path" ]; then
  info "下载 Codex 中文版: $BASE_URL/$ARCHIVE"
  download "$BASE_URL/$ARCHIVE" "$tmp/$ARCHIVE"
  [ "$(sha256_file "$tmp/$ARCHIVE")" = "$ARCHIVE_SHA256" ] || die "压缩包 sha256 不匹配"
  mv "$tmp/$ARCHIVE" "$archive_path"
else
  info "使用已缓存压缩包: $archive_path"
fi

tar -xzf "$archive_path" -C "$tmp"
src="$tmp/codex-${VERSION}-zh-${TARGET}"
[ -f "$src" ] || die "Codex 压缩包里没有二进制"
[ "$(sha256_file "$src")" = "$BIN_SHA256" ] || die "Codex 二进制 sha256 不匹配"

binary_path="$install_dir/codex-zh-bin"
launcher_path="$install_dir/$INSTALL_NAME"
cp "$src" "$binary_path"
chmod 755 "$binary_path"
create_launcher "$launcher_path" "$binary_path"

case ":${PATH:-}:" in
  *":$install_dir:"*) ;;
  *) warn "当前 PATH 不包含 $install_dir；本次会写入 shell 启动文件，当前会话也可以先运行: export PATH=\"$install_dir:\$PATH\"" ;;
esac

profile_file="$HOME/.profile"
if [ ! -f "$profile_file" ] || ! grep -F "$install_dir" "$profile_file" >/dev/null 2>&1; then
  {
    printf '\n# codex-zh\n'
    printf 'export PATH="%s:$PATH"\n' "$install_dir"
  } >> "$profile_file"
fi

models_file="$tmp/models.txt"
enabled_file="$tmp/enabled-models.txt"
: > "$enabled_file"

if [ "$SKIP_API_SETUP" != "1" ]; then
  info "配置第三方 Responses API"
  raw_base="$(tty_read "请输入 API Base URL，例如 https://api.example.com 或 https://api.example.com/v1" "")"
  api_key="$(tty_read_secret "请输入 API Key")"
  [ -n "$raw_base" ] || die "API Base URL 不能为空"
  [ -n "$api_key" ] || die "API Key 不能为空"
  api_base="$(normalize_api_base "$raw_base")"
  info "规范化后的 API Base URL: $api_base"

  models_json="$tmp/models.json"
  if curl -fsS --http1.1 -H "Authorization: Bearer $api_key" "$api_base/models" -o "$models_json"; then
    parse_models "$models_json" > "$models_file"
  else
    warn "获取模型列表失败，改为手动输入默认模型"
    : > "$models_file"
  fi

  if [ -s "$models_file" ]; then
    default_model="$(choose_model "$models_file")"
    select_enabled_models "$models_file" "$default_model" > "$enabled_file"
  else
    default_model="$(tty_read "请输入默认模型名" "gpt-5.4-mini")"
    printf '%s\n' "$default_model" > "$enabled_file"
  fi
  write_codex_config "$api_base" "$api_key" "$default_model" "$enabled_file"
else
  warn "跳过 API 配置，因为 CODEX_ZH_SKIP_API_SETUP=1"
fi

info "已安装二进制: $binary_path"
info "已安装命令: $launcher_path"

if [ "$SKIP_RUN" != "1" ]; then
  "$launcher_path" --version
fi

info "完成。当前会话如提示 codex not found，先运行："
info "export PATH=\"$install_dir:\$PATH\""
info "然后运行：$INSTALL_NAME"
