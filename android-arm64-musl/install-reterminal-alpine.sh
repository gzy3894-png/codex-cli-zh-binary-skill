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
MIRROR_PROFILE="${CODEX_ZH_MIRROR_PROFILE:-auto}"
SETUP_MODE="${CODEX_ZH_SETUP_MODE:-}"
ALLOW_MANUAL_MODEL="${CODEX_ZH_ALLOW_MANUAL_MODEL:-0}"

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
  part="$dest.part"
  if have curl; then
    curl -fL --http1.1 \
      --retry 8 --retry-delay 2 --retry-all-errors \
      --connect-timeout 20 --speed-time 30 --speed-limit 1024 \
      -C - -o "$part" "$url"
    mv "$part" "$dest"
  elif have wget; then
    wget -c -O "$part" --tries=8 --timeout=30 "$url"
    mv "$part" "$dest"
  else
    die "缺少 curl 或 wget"
  fi
}

write_apk_repositories() {
  mirror="$1"
  case "$mirror" in
    tuna)
      cat > /etc/apk/repositories <<'EOF'
http://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/main
http://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/community
EOF
      ;;
    bfsu)
      cat > /etc/apk/repositories <<'EOF'
http://mirrors.bfsu.edu.cn/alpine/v3.24/main
http://mirrors.bfsu.edu.cn/alpine/v3.24/community
EOF
      ;;
    official)
      cat > /etc/apk/repositories <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.24/main
https://dl-cdn.alpinelinux.org/alpine/v3.24/community
EOF
      ;;
  esac
}

apk_update_with_fallback() {
  if [ "$MIRROR_PROFILE" = "keep" ]; then
    apk update
    return
  fi

  if [ -w /etc/apk/repositories ]; then
    cp /etc/apk/repositories "/etc/apk/repositories.codex-zh.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi

  for mirror in tuna bfsu official; do
    if [ "$MIRROR_PROFILE" != "auto" ] && [ "$MIRROR_PROFILE" != "$mirror" ]; then
      continue
    fi
    info "尝试 Alpine 镜像: $mirror"
    write_apk_repositories "$mirror"
    if apk update; then
      return
    fi
    warn "$mirror 镜像 apk update 失败，继续尝试下一个"
  done

  die "apk update 失败。可以稍后重试，或设置 CODEX_ZH_MIRROR_PROFILE=keep 使用当前 /etc/apk/repositories。"
}

install_deps() {
  if [ "$SKIP_DEPS" = "1" ]; then
    warn "跳过依赖安装，因为 CODEX_ZH_SKIP_DEPS=1"
    return
  fi
  have apk || die "当前不是 Alpine 环境：找不到 apk。请切到 ReTerminal 的 Alpine 模式再运行。"

  info "安装 Alpine 依赖（$DEPS_PROFILE 模式）..."
  if [ "$(id -u)" = "0" ]; then
    apk_update_with_fallback
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
    apk add --no-cache dialog >/dev/null 2>&1 || warn "dialog 可选依赖安装失败；模型选择会退回编号输入。"
    apk add --no-cache bubblewrap >/dev/null 2>&1 || warn "bubblewrap 可选依赖安装失败；Codex 可能仍提示 bubblewrap 警告。"
  else
    die "apk 需要 root 权限。ReTerminal Alpine 通常默认是 root；如果不是，请切到 root shell，或设置 CODEX_ZH_SKIP_DEPS=1 自行安装依赖。"
  fi
}

choose_install_dir() {
  if [ -n "${CODEX_ZH_INSTALL_DIR:-}" ]; then
    printf '%s\n' "$CODEX_ZH_INSTALL_DIR"
    return
  fi
  if [ "$(id -u)" = "0" ]; then
    mkdir -p /usr/local/bin 2>/dev/null || true
    if [ -w /usr/local/bin ]; then
      printf '%s\n' "/usr/local/bin"
      return
    fi
  fi
  printf '%s\n' "$HOME/.local/bin"
}

persist_path() {
  dir="$1"
  case ":${PATH:-}:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:${PATH:-}" ;;
  esac

  mkdir -p "$HOME"
  for profile_file in "$HOME/.profile" "$HOME/.ashrc" "$HOME/.shrc"; do
    if [ ! -f "$profile_file" ] || ! grep -F "$dir" "$profile_file" >/dev/null 2>&1; then
      {
        printf '\n# codex-zh\n'
        printf 'export PATH="%s:$PATH"\n' "$dir"
      } >> "$profile_file"
    fi
  done

  if [ "$(id -u)" = "0" ] && [ -d /etc/profile.d ]; then
    cat > /etc/profile.d/codex-zh.sh <<EOF
case ":\${PATH:-}:" in
  *":$dir:"*) ;;
  *) export PATH="$dir:\${PATH:-}" ;;
esac
EOF
    chmod 644 /etc/profile.d/codex-zh.sh
  fi
}

ensure_bubblewrap_alias() {
  if have bubblewrap; then
    return
  fi
  if have bwrap && [ -w "$install_dir" ]; then
    ln -sf "$(command -v bwrap)" "$install_dir/bubblewrap" 2>/dev/null || true
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

tty_read_api_key() {
  prompt="$1"
  if [ "${CODEX_ZH_HIDE_API_KEY:-0}" = "1" ] && [ -r /dev/tty ]; then
    printf '%s（输入时不显示，粘贴后按回车）: ' "$prompt" > /dev/tty
    old_stty="$(stty -g < /dev/tty 2>/dev/null || true)"
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r ans < /dev/tty || ans=""
    [ -z "$old_stty" ] || stty "$old_stty" < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
  else
    ans="$(tty_read "$prompt（默认明文显示；如需隐藏可设置 CODEX_ZH_HIDE_API_KEY=1）" "")"
  fi
  printf '%s' "$ans"
}

choose_setup_mode() {
  case "$SETUP_MODE" in
    official|third_party)
      printf '%s\n' "$SETUP_MODE"
      return
      ;;
    "") ;;
    *)
      warn "未知 CODEX_ZH_SETUP_MODE=$SETUP_MODE，将显示选择菜单"
      ;;
  esac

  {
    printf '%s\n' "请选择 Codex 初始化方式："
    printf '%s\n' "1. 官方 Codex 初始化：不写第三方配置，首次运行 codex 时由官方流程提示登录或 API Key"
    printf '%s\n' "2. 第三方 Responses API：输入 Base URL 和 API Key，自动拉取模型并生成配置"
  } >&2
  choice="$(tty_read "请输入选项编号" "1")"
  case "$choice" in
    2) printf '%s\n' "third_party" ;;
    *) printf '%s\n' "official" ;;
  esac
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

fetch_models() {
  api_base="$1"
  api_key="$2"
  out_json="$3"
  err_file="$4"

  curl -fsS --http1.1 \
    -H "Authorization: Bearer $api_key" \
    -H "Accept: application/json" \
    "$api_base/models" \
    -o "$out_json" \
    2>"$err_file"
}

choose_model() {
  list_file="$1"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1
  printf '%s\n' "可用模型：" >&2
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

dialog_select_enabled_models() {
  list_file="$1"
  out_file="$2"
  have dialog || return 1
  [ -r /dev/tty ] || return 1
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1
  height=22
  [ "$count" -lt 14 ] && height=$((count + 8))
  cmd='dialog --clear --output-fd 1 --separate-output --checklist "空格选择/取消，回车确认。请选择要启用的模型：" '"$height"' 76 '"$count"
  while IFS= read -r model_name; do
    q="$(shell_quote "$model_name")"
    cmd="$cmd $q $q on"
  done < "$list_file"
  if eval "$cmd" >"$out_file" 2>/dev/tty </dev/tty; then
    [ -s "$out_file" ] || return 1
    return 0
  fi
  return 1
}

dialog_choose_default_model() {
  list_file="$1"
  have dialog || return 1
  [ -r /dev/tty ] || return 1
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1
  height=22
  [ "$count" -lt 14 ] && height=$((count + 8))
  cmd='dialog --clear --output-fd 1 --menu "请选择默认模型：" '"$height"' 76 '"$count"
  while IFS= read -r model_name; do
    q="$(shell_quote "$model_name")"
    cmd="$cmd $q $q"
  done < "$list_file"
  eval "$cmd" 2>/dev/tty </dev/tty
}

select_enabled_models_text() {
  list_file="$1"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  printf '%s\n' "可用模型：" >&2
  nl -w2 -s'. ' "$list_file" >&2
  picks="$(tty_read "启用哪些模型编号，逗号分隔；直接回车启用全部模型" "")"
  if [ -z "$picks" ]; then
    cat "$list_file"
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

select_models() {
  list_file="$1"
  enabled_file="$2"
  default_file="$3"

  if dialog_select_enabled_models "$list_file" "$enabled_file"; then
    :
  else
    warn "无法使用终端复选框，退回编号多选模式。"
    select_enabled_models_text "$list_file" > "$enabled_file"
  fi

  [ -s "$enabled_file" ] || die "没有选择任何模型，已停止。"

  if default_model="$(dialog_choose_default_model "$enabled_file")" && [ -n "$default_model" ]; then
    printf '%s\n' "$default_model" > "$default_file"
  else
    choose_model "$enabled_file" > "$default_file"
  fi
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
install_dir="$(choose_install_dir)"
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
  download "$BASE_URL/$ARCHIVE" "$archive_path"
  if [ "$(sha256_file "$archive_path")" != "$ARCHIVE_SHA256" ]; then
    bad_sha="$(sha256_file "$archive_path" 2>/dev/null || true)"
    rm -f "$archive_path" "$archive_path.part"
    die "压缩包 sha256 不匹配: $bad_sha。已删除损坏文件，请重新运行脚本。"
  fi
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

persist_path "$install_dir"
ensure_bubblewrap_alias

models_file="$tmp/models.txt"
enabled_file="$tmp/enabled-models.txt"
default_file="$tmp/default-model.txt"
: > "$enabled_file"

setup_mode="official"
if [ "$SKIP_API_SETUP" = "1" ]; then
  warn "跳过 API 配置，因为 CODEX_ZH_SKIP_API_SETUP=1"
else
  setup_mode="$(choose_setup_mode)"
fi

if [ "$setup_mode" = "third_party" ]; then
  info "配置第三方 Responses API"
  raw_base="${CODEX_ZH_API_BASE:-}"
  api_key="${CODEX_ZH_API_KEY:-}"
  [ -n "$raw_base" ] || raw_base="$(tty_read "请输入 API Base URL，例如 https://api.example.com 或 https://api.example.com/v1" "")"
  [ -n "$api_key" ] || api_key="$(tty_read_api_key "请输入 API Key")"
  [ -n "$raw_base" ] || die "API Base URL 不能为空"
  [ -n "$api_key" ] || die "API Key 不能为空"
  api_base="$(normalize_api_base "$raw_base")"
  info "规范化后的 API Base URL: $api_base"

  models_json="$tmp/models.json"
  models_err="$tmp/models.err"
  if fetch_models "$api_base" "$api_key" "$models_json" "$models_err"; then
    parse_models "$models_json" > "$models_file"
  else
    warn "获取模型列表失败：$api_base/models"
    if [ -s "$models_err" ]; then
      sed -n '1,20p' "$models_err" >&2 || true
    fi
    if [ "$ALLOW_MANUAL_MODEL" != "1" ]; then
      die "第三方 API 模式必须成功获取模型列表。请检查 Base URL、API Key、代理/网络；或显式设置 CODEX_ZH_ALLOW_MANUAL_MODEL=1 才允许手动输入模型名。"
    fi
    warn "允许手动模型兜底，因为 CODEX_ZH_ALLOW_MANUAL_MODEL=1"
    : > "$models_file"
  fi

  if [ -s "$models_file" ]; then
    select_models "$models_file" "$enabled_file" "$default_file"
    default_model="$(sed -n '1p' "$default_file")"
  else
    if [ "$ALLOW_MANUAL_MODEL" = "1" ]; then
      default_model="$(tty_read "请输入默认模型名" "gpt-5.4-mini")"
      printf '%s\n' "$default_model" > "$enabled_file"
    else
      if [ -s "$models_json" ]; then
        warn "接口返回了内容，但没有解析到 data[].id。返回片段："
        sed -n '1,20p' "$models_json" >&2 || true
      fi
      die "未从 /models 响应中解析到任何模型，已停止。"
    fi
  fi
  write_codex_config "$api_base" "$api_key" "$default_model" "$enabled_file"
else
  info "使用官方 Codex 初始化模式：不写第三方 provider/auth 配置。"
  if [ -s "${CODEX_HOME:-$HOME/.codex}/config.toml" ]; then
    warn "检测到已有 ${CODEX_HOME:-$HOME/.codex}/config.toml；脚本不会擅自覆盖或删除。若要完全走官方初始化，请先自行备份/移走旧配置。"
  fi
fi

info "已安装二进制: $binary_path"
info "已安装命令: $launcher_path"
if have bwrap; then
  info "bubblewrap 已安装: $(command -v bwrap)"
elif have bubblewrap; then
  info "bubblewrap 已安装: $(command -v bubblewrap)"
else
  warn "未找到 bubblewrap；如果 Codex 继续出现 bubblewrap 黄字，说明当前 Alpine 源没有成功安装 bubblewrap 或 Android/proot 环境不支持。Codex 会继续使用 bundled bubblewrap。"
fi

if [ "$SKIP_RUN" != "1" ]; then
  "$launcher_path" --version
fi

info "完成。现在可以直接运行：$INSTALL_NAME"
