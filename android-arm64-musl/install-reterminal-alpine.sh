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
INSTALLER_VERSION="${CODEX_FOR_TUI_INSTALLER_VERSION:-2026.07.01.2}"
STATE_ROOT="${CODEX_FOR_TUI_STATE_DIR:-${HOME:-/root}/.codex-for-tui}"
DOWNLOAD_METHOD_FILE="$STATE_ROOT/download-method"
DEPS_CONFIRM_FILE="$STATE_ROOT/deps-confirmed"
NOTICE_URL="${CODEX_FOR_TUI_NOTICE_URL:-}"
export PATH="/bin:/sbin:/usr/local/bin:/usr/bin:/usr/sbin:${HOME:-/root}/.local/bin:${PATH:-}"

info() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
upper() { tr '[:lower:]' '[:upper:]'; }
lower() { tr '[:upper:]' '[:lower:]'; }
is_root() { [ "${USER:-}" = "root" ] || [ "${UID:-}" = "0" ] || [ -w /etc/apk/repositories ]; }
clear_screen() { printf '\033[H\033[2J' 2>/dev/null || true; }

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
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

tty_available() {
  [ "${CODEX_ZH_FORCE_STDIN:-0}" = "1" ] && return 1
  [ -r /dev/tty ] && [ -w /dev/tty ] && { : < /dev/tty; } 2>/dev/null
}

deps_packages_minimal() {
  printf '%s\n' "ca-certificates curl wget tar gzip jq git openssh-client ripgrep fd bash sed grep gawk"
}

deps_packages_full() {
  printf '%s\n' "ca-certificates curl wget tar gzip unzip xz jq git openssh-client ripgrep fd bash sed grep gawk diffutils patch python3 py3-pip nodejs npm make gcc g++ musl-dev pkgconf cmake ninja openssl openssl-dev libffi-dev perl"
}

required_commands_for_profile() {
  if [ "$DEPS_PROFILE" = "minimal" ]; then
    printf '%s\n' "tar gzip jq git ssh rg fd bash sed grep awk"
  else
    printf '%s\n' "tar gzip unzip xz jq git ssh rg fd bash sed grep awk python3 node npm make gcc g++ cmake ninja openssl perl"
  fi
}

missing_commands() {
  required_commands_for_profile | tr ' ' '\n' | while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    have "$cmd" || printf '%s\n' "$cmd"
  done
}

available_downloaders() {
  have curl && printf '%s\n' "curl"
  have wget && printf '%s\n' "wget"
  have aria2c && printf '%s\n' "aria2c"
  if have busybox && busybox wget --help >/dev/null 2>&1; then
    printf '%s\n' "busybox-wget"
  fi
}

print_download_plan() {
  clear_screen
  cat >&2 <<EOF
Codex for TUI 环境检查

资源：
- Alpine 基础依赖
- Codex 中文版 ARM64 压缩包
- 可选开发依赖

预计下载总量：
- Minimal：约 150-250 MB
- Full：约 400-700 MB

网络：
- Alpine 镜像通常不一定需要代理。
- Codex 压缩包来自 GitHub raw，网络不稳时建议开启代理。
- 所有下载会尽量使用断点续传和重试。
EOF
  [ -n "$NOTICE_URL" ] && printf '%s\n' "公告地址：$NOTICE_URL" >&2
}

confirm_deps_install() {
  [ "$SKIP_DEPS" = "1" ] && return 0
  have apk || die "当前不是 Alpine 环境：找不到 apk。请切到 Codex for TUI 的 Alpine 模式再运行。"

  mkdir -p "$STATE_ROOT"
  missing="$(missing_commands | tr '\n' ' ')"
  if [ -z "$missing" ] && [ -s "$DEPS_CONFIRM_FILE" ]; then
    return 0
  fi

  print_download_plan
  if [ -n "$missing" ]; then
    printf '%s\n' "检测到缺失命令：$missing" >&2
  else
    printf '%s\n' "基础命令看起来已具备；你仍可选择补装/修复依赖。" >&2
  fi

  while :; do
    printf '%s\n' "请选择依赖安装方式：" >&2
    printf '%s\n' "1. 安装 Minimal 依赖（推荐：够 Codex 日常使用，体积较小）" >&2
    printf '%s\n' "2. 安装 Full 依赖（包含 python/node/gcc/cmake 等，体积较大）" >&2
    printf '%s\n' "3. 跳过依赖安装，直接继续" >&2
    printf '%s\n' "4. 退出，稍后再继续" >&2
    choice="$(tty_read "请输入选项编号" "$( [ "$DEPS_PROFILE" = "minimal" ] && printf 1 || printf 2 )")"
    case "$choice" in
      1)
        DEPS_PROFILE="minimal"
        printf '%s\n' "$DEPS_PROFILE" > "$DEPS_CONFIRM_FILE" 2>/dev/null || true
        return 0
        ;;
      2)
        DEPS_PROFILE="full"
        printf '%s\n' "$DEPS_PROFILE" > "$DEPS_CONFIRM_FILE" 2>/dev/null || true
        return 0
        ;;
      3)
        SKIP_DEPS=1
        return 0
        ;;
      4)
        info "已退出。重新打开 App 或再次运行安装脚本会继续。"
        exit 0
        ;;
      *) warn "请输入 1、2、3 或 4。" ;;
    esac
  done
}

install_download_tools_menu() {
  have apk || die "无法安装下载工具：当前环境缺少 apk。"
  while :; do
    printf '%s\n' "请选择要安装的下载工具：" >&2
    printf '%s\n' "1. curl（推荐，稳定支持断点续传/重试）" >&2
    printf '%s\n' "2. wget（兼容性好，参数简单）" >&2
    printf '%s\n' "3. aria2（多连接下载，网络好时更快）" >&2
    printf '%s\n' "4. curl + wget（推荐兜底组合）" >&2
    printf '%s\n' "5. curl + wget + aria2" >&2
    printf '%s\n' "6. 返回下载方式选择" >&2
    choice="$(tty_read "请输入选项编号" "4")"
    case "$choice" in
      1) tools="curl ca-certificates" ;;
      2) tools="wget ca-certificates" ;;
      3) tools="aria2 ca-certificates" ;;
      4) tools="curl wget ca-certificates" ;;
      5) tools="curl wget aria2 ca-certificates" ;;
      6) return 1 ;;
      *) warn "请输入 1-6。"; continue ;;
    esac
    printf '%s\n' "将通过 Alpine apk 安装：$tools" >&2
    printf '%s\n' "下载大小取决于镜像和已有缓存；通常几 MB 到几十 MB。Alpine 镜像一般不需要代理，若镜像连接失败会自动换源。" >&2
    apk_update_with_fallback >&2
    apk add --no-cache $tools >&2
    return 0
  done
}

choose_downloader() {
  mkdir -p "$STATE_ROOT"
  forced="${CODEX_ZH_DOWNLOADER:-}"
  if [ -z "$forced" ] && [ -s "$DOWNLOAD_METHOD_FILE" ]; then
    forced="$(sed -n '1p' "$DOWNLOAD_METHOD_FILE")"
  fi
  case "$forced" in
    curl|wget|aria2c|busybox-wget)
      if [ "$forced" = "busybox-wget" ]; then
        have busybox && busybox wget --help >/dev/null 2>&1 && { printf '%s\n' "$forced"; return 0; }
      elif have "$forced"; then
        printf '%s\n' "$forced"
        return 0
      fi
      warn "上次/指定下载方式 $forced 当前不可用，将重新选择。"
      ;;
  esac

  while :; do
    available="$(available_downloaders | tr '\n' ' ')"
    printf '\n%s\n' "请选择 Codex 压缩包下载方式：" >&2
    [ -n "$available" ] && printf '%s\n' "当前可用下载工具：$available" >&2 || printf '%s\n' "当前没有检测到可用下载工具。" >&2
    idx=1
    opts_file="$STATE_ROOT/download-options.$$"
    : > "$opts_file"
    if have curl; then
      printf '%s\n' "curl" >> "$opts_file"
      printf '%s\n' "$idx. curl：--http1.1 + 断点续传 + 8 次重试 + 低速保护（推荐）" >&2
      idx=$((idx + 1))
    fi
    if have wget; then
      printf '%s\n' "wget" >> "$opts_file"
      printf '%s\n' "$idx. wget：-c 断点续传 + 8 次重试 + 30 秒超时" >&2
      idx=$((idx + 1))
    fi
    if have aria2c; then
      printf '%s\n' "aria2c" >> "$opts_file"
      printf '%s\n' "$idx. aria2：断点续传 + 4 连接 + 8 次重试" >&2
      idx=$((idx + 1))
    fi
    if have busybox && busybox wget --help >/dev/null 2>&1; then
      printf '%s\n' "busybox-wget" >> "$opts_file"
      printf '%s\n' "$idx. busybox wget：最小兜底下载器，能力较弱" >&2
      idx=$((idx + 1))
    fi
    install_choice="$idx"
    printf '%s\n' "$install_choice. 安装/补装下载工具" >&2
    exit_choice=$((idx + 1))
    printf '%s\n' "$exit_choice. 退出，稍后再继续" >&2
    choice="$(tty_read "请输入选项编号" "1")"
    case "$choice" in
      *[!0-9]*|"") choice=1 ;;
    esac
    count="$(wc -l < "$opts_file" | tr -d ' ')"
    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ] 2>/dev/null; then
      method="$(sed -n "${choice}p" "$opts_file")"
      rm -f "$opts_file"
      printf '%s\n' "$method" > "$DOWNLOAD_METHOD_FILE" 2>/dev/null || true
      printf '%s\n' "$method"
      return 0
    fi
    rm -f "$opts_file"
    if [ "$choice" = "$install_choice" ]; then
      install_download_tools_menu || true
      continue
    fi
    if [ "$choice" = "$exit_choice" ]; then
      info "已退出。重新打开 App 或再次运行安装脚本会继续。"
      exit 0
    fi
    warn "请输入列表里的编号。"
  done
}

download() {
  url="$1"
  dest="$2"
  part="$dest.part"
  method="$(choose_downloader)"
  info "使用下载方式：$method"
  if [ "$method" = "curl" ]; then
    curl -fL --http1.1 \
      --retry 8 --retry-delay 2 --retry-all-errors \
      --connect-timeout 20 --speed-time 30 --speed-limit 1024 \
      -C - -o "$part" "$url"
    mv "$part" "$dest"
  elif [ "$method" = "wget" ]; then
    wget -c -O "$part" --tries=8 --timeout=30 "$url"
    mv "$part" "$dest"
  elif [ "$method" = "aria2c" ]; then
    rm -f "$part.aria2"
    aria2c -c -x 4 -s 4 --retry-wait=2 --max-tries=8 --connect-timeout=20 --timeout=60 \
      -d "$(dirname "$part")" -o "$(basename "$part")" "$url"
    mv "$part" "$dest"
  elif [ "$method" = "busybox-wget" ]; then
    busybox wget -c -O "$part" "$url"
    mv "$part" "$dest"
  else
    die "未知下载方式：$method"
  fi
}

write_apk_repositories() {
  mirror="$1"
  alpine_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release 2>/dev/null | tr -d '"' | awk -F. '{print $1 "." $2}')"
  [ -n "$alpine_version" ] || alpine_version="3.24"
  case "$mirror" in
    tuna)
      cat > /etc/apk/repositories <<EOF
http://mirrors.tuna.tsinghua.edu.cn/alpine/v$alpine_version/main
http://mirrors.tuna.tsinghua.edu.cn/alpine/v$alpine_version/community
EOF
      ;;
    bfsu)
      cat > /etc/apk/repositories <<EOF
http://mirrors.bfsu.edu.cn/alpine/v$alpine_version/main
http://mirrors.bfsu.edu.cn/alpine/v$alpine_version/community
EOF
      ;;
    official)
      cat > /etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/v$alpine_version/main
https://dl-cdn.alpinelinux.org/alpine/v$alpine_version/community
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
  have apk || die "当前不是 Alpine 环境：找不到 apk。请切到 Codex for TUI 的 Alpine 模式再运行。"

  info "安装 Alpine 依赖（$DEPS_PROFILE 模式）..."
  if is_root; then
    apk_update_with_fallback
    if [ "$DEPS_PROFILE" = "minimal" ]; then
      apk add --no-cache $(deps_packages_minimal)
    else
      apk add --no-cache $(deps_packages_full)
    fi
    apk add --no-cache bubblewrap >/dev/null 2>&1 || warn "bubblewrap 可选依赖安装失败；Codex 可能仍提示 bubblewrap 警告。"
  else
    die "apk 需要 root 权限。Codex for TUI Alpine 通常默认是 root；如果不是，请切到 root shell，或设置 CODEX_ZH_SKIP_DEPS=1 自行安装依赖。"
  fi
}

choose_install_dir() {
  if [ -n "${CODEX_ZH_INSTALL_DIR:-}" ]; then
    printf '%s\n' "$CODEX_ZH_INSTALL_DIR"
    return
  fi
  if is_root; then
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

  if is_root && [ -d /etc/profile.d ]; then
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
  mode_lc="$(printf '%s' "$SETUP_MODE" | lower)"
  case "$mode_lc" in
    official|third_party)
      printf '%s\n' "$mode_lc"
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
  choice_lc="$(printf '%s' "$choice" | lower)"
  case "$choice_lc" in
    2|third_party|third-party|api|custom|第三方) printf '%s\n' "third_party" ;;
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
  printf '\n%s\n' "请选择默认启动模型：" >&2
  printf '%s\n' "这个模型会写入 config.toml 的 model 字段，Codex 启动后会默认使用它；其他已启用模型仍可在 /model 中切换。" >&2
  nl -w2 -s'. ' "$list_file" >&2
  choice="$(tty_read "请输入默认启动模型编号" "1")"
  case "$choice" in
    *[!0-9]*|"") choice=1 ;;
  esac
  if [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "$count" ] 2>/dev/null; then
    choice=1
  fi
  chosen="$(sed -n "${choice}p" "$list_file")"
  printf '已选择默认启动模型：%s\n' "$chosen" >&2
  printf '%s\n' "$chosen"
}

select_enabled_models_text() {
  list_file="$1"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1

  selected="$tmp/selected-model-indexes.txt"
  : > "$selected"
  seq 1 "$count" > "$selected"

  while :; do
    printf '\n%s\n' "选择要启用的模型（默认已全选）：" >&2
    i=1
    while [ "$i" -le "$count" ]; do
      model_name="$(sed -n "${i}p" "$list_file")"
      if grep -x "$i" "$selected" >/dev/null 2>&1; then
        mark="x"
      else
        mark=" "
      fi
      printf '  [%s] %2s. %s\n' "$mark" "$i" "$model_name" >&2
      i=$((i + 1))
    done
    printf '%s\n' "操作：输入编号切换选择，多个编号可用空格/逗号分隔；a=全选，n=清空。" >&2
    printf '%s\n' "选好了直接按回车即可；也可以输入 d/done 完成。" >&2
    picks="$(tty_read "多选操作（回车=完成）" "")"
    picks_lc="$(printf '%s' "$picks" | lower | tr ',' ' ')"
    case "$picks_lc" in
      ""|d|done|ok|y|yes|完成)
        break
        ;;
      a|all|全选)
        seq 1 "$count" > "$selected"
        printf '%s\n' "已全选。选好了直接按回车。" >&2
        continue
        ;;
      n|none|clear|清空)
        : > "$selected"
        printf '%s\n' "已清空选择。请至少选择一个模型，或继续按回车使用全部模型兜底。" >&2
        continue
        ;;
    esac

    printf '%s\n' "$picks_lc" | tr ' ' '\n' | while IFS= read -r n; do
      n="$(printf '%s' "$n" | sed 's/[^0-9]//g')"
      [ -n "$n" ] || continue
      [ "$n" -ge 1 ] 2>/dev/null || continue
      [ "$n" -le "$count" ] 2>/dev/null || continue
      if grep -x "$n" "$selected" >/dev/null 2>&1; then
        grep -vx "$n" "$selected" > "$selected.tmp" || true
        mv "$selected.tmp" "$selected"
      else
        printf '%s\n' "$n" >> "$selected"
        sort -n -u "$selected" -o "$selected"
      fi
    done
    printf '%s\n' "已更新选择。选好了直接按回车完成；还要调整就继续输入编号。" >&2
  done

  if [ ! -s "$selected" ]; then
    warn "未选择任何模型，默认启用全部模型。"
    cat "$list_file"
    return
  fi

  while IFS= read -r n; do
    sed -n "${n}p" "$list_file"
  done < "$selected"
}

select_models() {
  list_file="$1"
  enabled_file="$2"
  default_file="$3"

  select_enabled_models_text "$list_file" > "$enabled_file"

  [ -s "$enabled_file" ] || die "没有选择任何模型，已停止。"

  choose_model "$enabled_file" > "$default_file"
}

write_model_catalog_entry() {
  model_name="$1"
  priority="$2"
  need_comma="$3"
  model_name_esc="$(json_escape "$model_name")"

  if [ "$need_comma" = "1" ]; then
    printf ',\n'
  fi
  printf '    {\n'
  printf '      "slug": "%s",\n' "$model_name_esc"
  printf '      "display_name": "%s",\n' "$model_name_esc"
  printf '      "description": "Third-party API model",\n'
  printf '      "default_reasoning_level": "medium",\n'
  printf '      "supported_reasoning_levels": [\n'
  printf '        {"effort": "low", "description": "Fast responses with lighter reasoning"},\n'
  printf '        {"effort": "medium", "description": "Balances speed and reasoning depth"},\n'
  printf '        {"effort": "high", "description": "Greater reasoning depth"},\n'
  printf '        {"effort": "xhigh", "description": "Extra high reasoning depth"}\n'
  printf '      ],\n'
  printf '      "shell_type": "shell_command",\n'
  printf '      "visibility": "list",\n'
  printf '      "supported_in_api": true,\n'
  printf '      "priority": %s,\n' "$priority"
  printf '      "availability_nux": null,\n'
  printf '      "upgrade": null,\n'
  printf '      "base_instructions": "",\n'
  printf '      "model_messages": null,\n'
  printf '      "supports_reasoning_summaries": true,\n'
  printf '      "default_reasoning_summary": "auto",\n'
  printf '      "support_verbosity": false,\n'
  printf '      "default_verbosity": null,\n'
  printf '      "apply_patch_tool_type": null,\n'
  printf '      "web_search_tool_type": "text",\n'
  printf '      "truncation_policy": {"mode": "tokens", "limit": 10000},\n'
  printf '      "supports_parallel_tool_calls": true,\n'
  printf '      "supports_image_detail_original": false,\n'
  printf '      "context_window": 120000,\n'
  printf '      "max_context_window": 120000,\n'
  printf '      "auto_compact_token_limit": null,\n'
  printf '      "effective_context_window_percent": 95,\n'
  printf '      "experimental_supported_tools": [],\n'
  printf '      "input_modalities": ["text"],\n'
  printf '      "supports_search_tool": false,\n'
  printf '      "use_responses_lite": false\n'
  printf '    }'
}

write_model_catalog_json() {
  catalog_file="$1"
  enabled_file="$2"
  default_model="$3"

  first=1
  priority=0
  {
    printf '{\n'
    printf '  "models": [\n'
    if [ -n "$default_model" ]; then
      write_model_catalog_entry "$default_model" "$priority" "0"
      first=0
      priority=$((priority + 10))
    fi
    if [ -s "$enabled_file" ]; then
      while IFS= read -r model_name; do
        [ -n "$model_name" ] || continue
        [ "$model_name" = "$default_model" ] && continue
        if [ "$first" -eq 1 ]; then
          need_comma=0
          first=0
        else
          need_comma=1
        fi
        write_model_catalog_entry "$model_name" "$priority" "$need_comma"
        priority=$((priority + 10))
      done < "$enabled_file"
    fi
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } > "$catalog_file"
  chmod 600 "$catalog_file"
}

write_codex_config() {
  api_base="$1"
  api_key="$2"
  default_model="$3"
  enabled_file="$4"

  codex_home="${CODEX_HOME:-$HOME/.codex}"
  mkdir -p "$codex_home"
  chmod 700 "$codex_home"

  auth_file="$codex_home/auth.json"
  {
    printf '{\n'
    printf '  "OPENAI_API_KEY": "%s"\n' "$(json_escape "$api_key")"
    printf '}\n'
  } > "$auth_file"
  chmod 600 "$auth_file"

  config_file="$codex_home/config.toml"
  catalog_file="$codex_home/model-catalog.json"
  write_model_catalog_json "$catalog_file" "$enabled_file" "$default_model"

  provider_id_esc="$(toml_escape "$PROVIDER_ID")"
  default_model_esc="$(toml_escape "$default_model")"
  api_base_esc="$(toml_escape "$api_base")"
  home_esc="$(toml_escape "$HOME")"
  catalog_file_esc="$(toml_escape "$catalog_file")"
  {
    printf 'model_provider = "%s"\n' "$provider_id_esc"
    printf 'model = "%s"\n' "$default_model_esc"
    printf 'model_catalog_json = "%s"\n' "$catalog_file_esc"
    printf 'model_reasoning_effort = "medium"\n'
    printf 'model_auto_compact_token_limit = 120000\n'
    printf 'disable_response_storage = true\n'
    printf '\n[features]\n'
    printf 'hooks = false\n'
    printf '\n[model_providers.%s]\n' "$PROVIDER_ID"
    printf 'name = "%s"\n' "$provider_id_esc"
    printf 'base_url = "%s"\n' "$api_base_esc"
    printf 'wire_api = "responses"\n'
    printf 'requires_openai_auth = true\n'
    printf '\n[projects."%s"]\n' "$home_esc"
    printf 'trust_level = "trusted"\n'
    printf '\n[tui]\n'
    printf 'status_line = ["model-with-reasoning", "current-dir", "context-remaining"]\n'
    printf 'status_line_use_colors = true\n'
  } > "$config_file"
  chmod 600 "$config_file"
}

write_standard_agents() {
  out="$1"
  cat > "$out" <<'EOF'
# AGENTS.md

## 身份
- 你是 Codex，运行在 Android/Codex for TUI Alpine 环境中的编程助手。
- 优先帮助用户把事情做完，回答简洁、可执行。

## 工作方式
- 修改文件前先理解上下文。
- 不要擅自删除或覆盖用户文件。
- 遇到不确定或高风险操作先确认。
- 优先使用 rg、sed、git 等本地工具验证。

## 输出
- 先给结论，再给必要步骤。
- 如果命令失败，说明原因和下一步。
EOF
}

setup_agents_md() {
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  mkdir -p "$codex_home"
  chmod 700 "$codex_home"

  info "配置启动提示词 AGENTS.md"
  printf '%s\n' "请选择启动提示词：" >&2
  printf '%s\n' "1. 默认 AGENTS.md：生成标准版系统提示词，每次启动自动带上" >&2
  printf '%s\n' "2. 自定义 AGENTS.md：现在粘贴你的内容" >&2
  choice="$(tty_read "请输入选项编号" "1")"
  choice_lc="$(printf '%s' "$choice" | lower)"

  agents_file="$codex_home/AGENTS.md"
  home_agents="$HOME/AGENTS.md"
  rm -f "$codex_home/AGENTS.standard.md"

  case "$choice_lc" in
    2|custom|自定义)
      info "请输入自定义 AGENTS.md 内容。单独输入一行 EOF 结束。"
      : > "$agents_file"
      while :; do
        if [ -r /dev/tty ]; then
          IFS= read -r line < /dev/tty || break
        else
          IFS= read -r line || break
        fi
        [ "$line" = "EOF" ] && break
        printf '%s\n' "$line" >> "$agents_file"
      done
      if [ ! -s "$agents_file" ]; then
        warn "自定义 AGENTS.md 为空，回退到默认版。"
        write_standard_agents "$agents_file"
      fi
      ;;
    *)
      write_standard_agents "$agents_file"
      ;;
  esac

  cp "$agents_file" "$home_agents"
  chmod 600 "$agents_file" "$home_agents" 2>/dev/null || true
}

create_launcher() {
  path="$1"
  binary="$2"
  binary_q="$(shell_quote "$binary")"
  cat > "$path" <<EOF
#!/usr/bin/env sh
export HOME="\${HOME:-/root}"
export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"
export PATH="\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:\${PATH:-}"
if [ ! -s "\$HOME/AGENTS.md" ] && [ -s "\$CODEX_HOME/AGENTS.md" ]; then
  cp "\$CODEX_HOME/AGENTS.md" "\$HOME/AGENTS.md" 2>/dev/null || true
fi
exec $binary_q "\$@"
EOF
  chmod 755 "$path"
}

install_case_variants() {
  dir="$1"
  target="$2"
  for c in c C; do
    for o in o O; do
      for d in d D; do
        for e in e E; do
          for x in x X; do
            link="$dir/$c$o$d$e$x"
            [ "$link" = "$target" ] && continue
            ln -sf "$target" "$link" 2>/dev/null || true
          done
        done
      done
    done
  done
}

arch="$(uname -m 2>/dev/null || printf unknown)"
case "$arch" in
  aarch64|arm64) ;;
  *) warn "这个安装器面向 Android ARM64；当前架构是 $arch" ;;
esac

[ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
mkdir -p "$HOME"
STATE_ROOT="${CODEX_FOR_TUI_STATE_DIR:-$HOME/.codex-for-tui}"
DOWNLOAD_METHOD_FILE="$STATE_ROOT/download-method"
DEPS_CONFIRM_FILE="$STATE_ROOT/deps-confirmed"

confirm_deps_install
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
install_case_variants "$install_dir" "$launcher_path"

persist_path "$install_dir"
ensure_bubblewrap_alias

resume_src=""
script_dir="$(dirname "$0" 2>/dev/null || printf '.')"
if [ -s "$script_dir/codex-local-resume.sh" ]; then
  resume_src="$script_dir/codex-local-resume.sh"
fi

if [ -n "$resume_src" ]; then
  resume_path="$install_dir/codex-local-resume"
  cp "$resume_src" "$resume_path"
  chmod 755 "$resume_path"
  info "进入可恢复的本地配置流程：$resume_path"
  CODEX_ZH_SKIP_RUN=1 \
    CODEX_ZH_INSTALL_DIR="$install_dir" \
    CODEX_HOME="${CODEX_HOME:-$HOME/.codex}" \
    "$resume_path"
  if [ "$SKIP_RUN" != "1" ]; then
    info "安装配置完成，正在启动 Codex..."
    exec "$launcher_path"
  fi
  info "完成。现在可以直接运行：$INSTALL_NAME"
  exit 0
fi

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

setup_agents_md

info "已安装二进制: $binary_path"
info "已安装命令: $launcher_path"
info "已安装大小写兼容入口: codex / Codex / CODEX / 其余大小写组合"
if have bwrap; then
  info "bubblewrap 已安装: $(command -v bwrap)"
elif have bubblewrap; then
  info "bubblewrap 已安装: $(command -v bubblewrap)"
else
  warn "未找到 bubblewrap；如果 Codex 继续出现 bubblewrap 黄字，说明当前 Alpine 源没有成功安装 bubblewrap 或 Android/proot 环境不支持。Codex 会继续使用 bundled bubblewrap。"
fi

if [ "$SKIP_RUN" != "1" ]; then
  info "安装配置完成，正在启动 Codex..."
  exec "$launcher_path"
fi

info "完成。现在可以直接运行：$INSTALL_NAME"
