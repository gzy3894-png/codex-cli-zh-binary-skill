#!/usr/bin/env sh
set -eu

VERSION="0.142.4"
TARGET="aarch64-unknown-linux-musl"
BRANCH="${CODEX_ZH_BRANCH:-android-arm64-musl-installer}"
REPO_RAW="${CODEX_ZH_REPO_RAW:-https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
BASE_URL="${CODEX_ZH_BASE_URL:-$REPO_RAW/$BRANCH/android-arm64-musl}"
BINARY_BASE_URL="${CODEX_ZH_BINARY_BASE_URL:-https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/download/codex-for-tui-v1.0.0}"
CODEX_ARCHIVE="codex-${VERSION}-zh-${TARGET}.tar.gz"
CODEX_ARCHIVE_URL="$BINARY_BASE_URL/$CODEX_ARCHIVE"
CODEX_ARCHIVE_SHA256="7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29"
CODEX_BIN_SHA256="40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423"

ALPINE_VERSION="${CODEX_ZH_ALPINE_VERSION:-3.24.1}"
ALPINE_ROOTFS="alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
ALPINE_URL="${CODEX_ZH_ALPINE_URL:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/$ALPINE_ROOTFS}"
ALPINE_SHA256="${CODEX_ZH_ALPINE_SHA256:-F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259}"

INSTALL_NAME="${CODEX_ZH_INSTALL_NAME:-codex}"
ALIAS_NAME="${CODEX_ZH_ALIAS_NAME:-codex-alpine}"
PROVIDER_ID="${CODEX_ZH_PROVIDER_ID:-custom}"
WORKDIR_NAME="${CODEX_ZH_WORKDIR_NAME:-codex-alpine}"
SKIP_API_SETUP="${CODEX_ZH_SKIP_API_SETUP:-0}"
SKIP_RUN="${CODEX_ZH_SKIP_RUN:-0}"

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

apt_get_noninteractive() {
  DEBIAN_FRONTEND=noninteractive apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    "$@"
}

install_termux_deps() {
  [ -n "${PREFIX:-}" ] || die "请在 Termux 里运行本脚本"
  [ "$(id -u)" != "0" ] || die "不要在 su/root shell 里运行；请回到普通 Termux 用户"
  have apt-get || die "当前环境没有 apt-get/pkg，不像标准 Termux"

  info "安装 Termux 侧依赖..."
  DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a >/dev/null 2>&1 || true
  apt_get_noninteractive update
  apt_get_noninteractive install -y ca-certificates curl tar gzip proot coreutils sed grep gawk jq
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
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
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
  rootfs="$1"
  api_base="$2"
  api_key="$3"
  default_model="$4"
  enabled_file="$5"

  codex_home="$rootfs/root/.codex"
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
    printf '\n[projects."/root"]\n'
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

proot_run() {
  rootfs="$1"
  shift
  proot -0 -r "$rootfs" \
    -b /dev -b /proc -b /sys \
    -b "$HOME:/termux-home" \
    -b /sdcard:/sdcard \
    -w /root \
    /usr/bin/env -i HOME=/root USER=root LOGNAME=root TERM="${TERM:-xterm-256color}" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

create_launcher() {
  path="$1"
  rootfs="$2"
  rootfs_q="$(shell_quote "$rootfs")"
  cat > "$path" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
rootfs=$rootfs_q
env_file="\$rootfs/root/.codex/env"
if [ -r "\$env_file" ]; then
  . "\$env_file"
  export OPENAI_API_KEY
fi
exec proot -0 -r "\$rootfs" \\
  -b /dev -b /proc -b /sys \\
  -b "\$HOME:/termux-home" \\
  -b /sdcard:/sdcard \\
  -w /root \\
  /usr/bin/env -i HOME=/root USER=root LOGNAME=root TERM="\${TERM:-xterm-256color}" \\
  OPENAI_API_KEY="\${OPENAI_API_KEY:-}" \\
  PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\
  /root/.local/bin/codex "\$@"
EOF
  chmod 755 "$path"
}

case "$(uname -m 2>/dev/null || true)" in
  aarch64|arm64) ;;
  *) warn "这个安装器面向 Android ARM64；当前架构是 $(uname -m 2>/dev/null || echo unknown)" ;;
esac

install_termux_deps

cache_dir="${PREFIX}/var/cache/codex-zh"
state_dir="${PREFIX}/var/lib/codex-zh"
rootfs="$state_dir/$WORKDIR_NAME/rootfs"
tmp="${TMPDIR:-$PREFIX/tmp}/codex-zh-alpine.$$"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$cache_dir" "$state_dir" "$tmp"

alpine_path="$cache_dir/$ALPINE_ROOTFS"
if [ -f "$alpine_path" ] && [ "$(sha256_file "$alpine_path")" != "$ALPINE_SHA256" ]; then
  warn "Alpine rootfs 缓存校验失败，将重新下载"
  rm -f "$alpine_path"
fi
if [ ! -f "$alpine_path" ]; then
  info "下载 Alpine rootfs: $ALPINE_URL"
  download "$ALPINE_URL" "$tmp/$ALPINE_ROOTFS"
  [ "$(sha256_file "$tmp/$ALPINE_ROOTFS")" = "$ALPINE_SHA256" ] || die "Alpine rootfs sha256 不匹配"
  mv "$tmp/$ALPINE_ROOTFS" "$alpine_path"
fi

codex_archive="$cache_dir/$CODEX_ARCHIVE"
if [ -f "$codex_archive" ] && [ "$(sha256_file "$codex_archive")" != "$CODEX_ARCHIVE_SHA256" ]; then
  warn "Codex 压缩包缓存校验失败，将重新下载"
  rm -f "$codex_archive"
fi
if [ ! -f "$codex_archive" ]; then
  info "下载 Codex 中文版: $CODEX_ARCHIVE_URL"
  download "$CODEX_ARCHIVE_URL" "$tmp/$CODEX_ARCHIVE"
  [ "$(sha256_file "$tmp/$CODEX_ARCHIVE")" = "$CODEX_ARCHIVE_SHA256" ] || die "Codex 压缩包 sha256 不匹配"
  mv "$tmp/$CODEX_ARCHIVE" "$codex_archive"
fi

if [ ! -d "$rootfs" ] || [ ! -x "$rootfs/bin/sh" ]; then
  info "安装 Alpine rootfs 到 $rootfs"
  rm -rf "$rootfs"
  mkdir -p "$rootfs"
  tar -xzf "$alpine_path" -C "$rootfs"
fi

mkdir -p "$rootfs/etc/apk" "$rootfs/root/.local/bin"
cat > "$rootfs/etc/apk/repositories" <<'EOF'
http://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/main
http://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/community
EOF

info "安装 Alpine 内依赖..."
if ! proot_run "$rootfs" /sbin/apk update; then
  warn "TUNA mirror 失败，切换 BFSU mirror 重试"
  cat > "$rootfs/etc/apk/repositories" <<'EOF'
http://mirrors.bfsu.edu.cn/alpine/v3.24/main
http://mirrors.bfsu.edu.cn/alpine/v3.24/community
EOF
  proot_run "$rootfs" /sbin/apk update
fi
proot_run "$rootfs" /sbin/apk add --no-cache ca-certificates curl jq git openssh-client ripgrep fd bash coreutils findutils sed grep gawk procps

tar -xzf "$codex_archive" -C "$tmp"
src="$tmp/codex-${VERSION}-zh-${TARGET}"
[ -f "$src" ] || die "Codex 压缩包里没有二进制"
[ "$(sha256_file "$src")" = "$CODEX_BIN_SHA256" ] || die "Codex 二进制 sha256 不匹配"
cp "$src" "$rootfs/root/.local/bin/codex-zh-bin"
chmod 755 "$rootfs/root/.local/bin/codex-zh-bin"
ln -sf /root/.local/bin/codex-zh-bin "$rootfs/root/.local/bin/codex"

models_file="$tmp/models.txt"
enabled_file="$tmp/enabled-models.txt"
: > "$enabled_file"
api_base=""
api_key=""
default_model=""

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
  write_codex_config "$rootfs" "$api_base" "$api_key" "$default_model" "$enabled_file"
else
  warn "跳过 API 配置，因为 CODEX_ZH_SKIP_API_SETUP=1"
fi

install_dir="$PREFIX/bin"
main_launcher="$install_dir/$INSTALL_NAME"
alias_launcher="$install_dir/$ALIAS_NAME"
if [ -e "$main_launcher" ] || [ -L "$main_launcher" ]; then
  backup="$main_launcher.bak.$(date +%Y%m%d%H%M%S)"
  info "备份已有 $main_launcher 到 $backup"
  mv "$main_launcher" "$backup"
fi
create_launcher "$main_launcher" "$rootfs"
if [ "$ALIAS_NAME" != "$INSTALL_NAME" ]; then
  create_launcher "$alias_launcher" "$rootfs"
fi

info "已安装 Alpine rootfs: $rootfs"
info "已安装命令: $main_launcher"
[ "$ALIAS_NAME" = "$INSTALL_NAME" ] || info "备用命令: $alias_launcher"

if [ "$SKIP_RUN" != "1" ]; then
  "$main_launcher" --version
fi

info "完成。现在可以运行: $INSTALL_NAME"
