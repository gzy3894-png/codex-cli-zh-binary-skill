#!/usr/bin/env sh
set -eu

VERSION="0.142.4"
TARGET="aarch64-unknown-linux-musl"
REPO_RAW="${CODEX_ZH_REPO_RAW:-https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill}"
BRANCH="${CODEX_ZH_BRANCH:-android-arm64-musl-installer}"
BASE_URL="${CODEX_ZH_BASE_URL:-$REPO_RAW/$BRANCH/android-arm64-musl}"
ARCHIVE="codex-${VERSION}-zh-${TARGET}.tar.gz"
ARCHIVE_SHA256="7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29"
BIN_SHA256="40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423"
INSTALL_NAME="${CODEX_ZH_INSTALL_NAME:-codex}"
SKIP_DEPS="${CODEX_ZH_SKIP_DEPS:-0}"
SKIP_RUN="${CODEX_ZH_SKIP_RUN:-0}"
DEPS_PROFILE="${CODEX_ZH_DEPS_PROFILE:-full}"

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '警告: %s\n' "$*" >&2
}

die() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

upper() {
  tr '[:lower:]' '[:upper:]'
}

sha256_file() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}' | upper
    return
  fi
  if have openssl; then
    openssl dgst -sha256 "$1" | awk '{print $2}' | upper
    return
  fi
  die "缺少 sha256sum 或 openssl"
}

setup_noninteractive_apt() {
  : "${DEBIAN_FRONTEND:=noninteractive}"
  : "${APT_LISTCHANGES_FRONTEND:=none}"
  : "${UCF_FORCE_CONFOLD:=1}"
  export DEBIAN_FRONTEND APT_LISTCHANGES_FRONTEND UCF_FORCE_CONFOLD
}

apt_get_noninteractive() {
  $APT \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    "$@"
}

dpkg_configure_noninteractive() {
  if ! have dpkg; then
    return
  fi

  if [ "${1:-}" = "sudo" ]; then
    sudo dpkg --force-confdef --force-confold --configure -a || true
  else
    dpkg --force-confdef --force-confold --configure -a || true
  fi
}

install_deps() {
  if [ "$SKIP_DEPS" = "1" ]; then
    info "跳过依赖安装，因为 CODEX_ZH_SKIP_DEPS=1"
    return
  fi

  setup_noninteractive_apt

  if have pkg && [ -n "${PREFIX:-}" ]; then
    APT="apt-get"
    info "安装 Termux 依赖（$DEPS_PROFILE 模式，自动保留已有配置文件）..."
    dpkg_configure_noninteractive
    apt_get_noninteractive update
    if [ "$DEPS_PROFILE" = "minimal" ]; then
      apt_get_noninteractive install -y ca-certificates curl wget tar gzip git openssh ripgrep jq
      apt_get_noninteractive install -y fd >/dev/null 2>&1 || true
    else
      apt_get_noninteractive install -y \
        ca-certificates curl wget tar gzip unzip xz-utils \
        git openssh ripgrep fd jq \
        python python-pip nodejs npm \
        coreutils findutils sed grep gawk diffutils patch \
        bash make clang binutils lld pkg-config cmake ninja \
        openssl libffi perl procps termux-tools
    fi
    return
  fi

  if have apt-get; then
    info "安装 Debian/Ubuntu 依赖（$DEPS_PROFILE 模式，自动保留已有配置文件）..."
    if [ "$(id -u)" = "0" ]; then
      APT="apt-get"
      dpkg_configure_noninteractive
    elif have sudo; then
      APT="sudo apt-get"
      dpkg_configure_noninteractive sudo
    else
      warn "找到 apt-get，但没有 sudo/root 权限；跳过依赖安装"
      return
    fi
    apt_get_noninteractive update
    if [ "$DEPS_PROFILE" = "minimal" ]; then
      apt_get_noninteractive install -y ca-certificates curl wget tar gzip git openssh-client ripgrep jq fd-find
    else
      apt_get_noninteractive install -y \
        ca-certificates curl wget tar gzip unzip xz-utils \
        git openssh-client ripgrep fd-find jq \
        python3 python3-pip nodejs npm \
        coreutils findutils sed grep gawk diffutils patch \
        bash make gcc g++ pkg-config cmake ninja-build \
        openssl libssl-dev libffi-dev perl procps
    fi
    return
  fi

  if have apk; then
    info "安装 Alpine 依赖（$DEPS_PROFILE 模式）..."
    if [ "$(id -u)" = "0" ]; then
      if [ "$DEPS_PROFILE" = "minimal" ]; then
        apk add --no-cache ca-certificates curl wget tar gzip git openssh-client ripgrep fd jq
      else
        apk add --no-cache \
          ca-certificates curl wget tar gzip unzip xz \
          git openssh-client ripgrep fd jq \
          python3 py3-pip nodejs npm \
          coreutils findutils sed grep gawk diffutils patch \
          bash make gcc g++ musl-dev pkgconf cmake ninja \
          openssl openssl-dev libffi-dev perl procps
      fi
    elif have sudo; then
      if [ "$DEPS_PROFILE" = "minimal" ]; then
        sudo apk add --no-cache ca-certificates curl wget tar gzip git openssh-client ripgrep fd jq
      else
        sudo apk add --no-cache \
          ca-certificates curl wget tar gzip unzip xz \
          git openssh-client ripgrep fd jq \
          python3 py3-pip nodejs npm \
          coreutils findutils sed grep gawk diffutils patch \
          bash make gcc g++ musl-dev pkgconf cmake ninja \
          openssl openssl-dev libffi-dev perl procps
      fi
    else
      warn "找到 apk，但没有 sudo/root 权限；跳过依赖安装"
    fi
    return
  fi

  warn "未找到支持的包管理器；不安装依赖，继续执行"
}

choose_install_dir() {
  if [ -n "${CODEX_ZH_INSTALL_DIR:-}" ]; then
    printf '%s\n' "$CODEX_ZH_INSTALL_DIR"
    return
  fi
  if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/bin" ] && [ -w "$PREFIX/bin" ]; then
    printf '%s\n' "$PREFIX/bin"
    return
  fi
  printf '%s\n' "$HOME/.local/bin"
}

download() {
  url="$1"
  dest="$2"
  if have curl; then
    curl -fL --retry 3 --connect-timeout 20 -o "$dest" "$url"
    return
  fi
  if have wget; then
    wget -O "$dest" "$url"
    return
  fi
  die "缺少 curl 或 wget"
}

choose_cache_dir() {
  if [ -n "${CODEX_ZH_CACHE_DIR:-}" ]; then
    printf '%s\n' "$CODEX_ZH_CACHE_DIR"
    return
  fi
  if [ -n "${PREFIX:-}" ]; then
    printf '%s\n' "$PREFIX/var/cache/codex-zh"
    return
  fi
  printf '%s\n' "$HOME/.cache/codex-zh"
}

case "$(uname -m 2>/dev/null || true)" in
  aarch64|arm64) ;;
  *) warn "这个包是 Android/Linux ARM64 构建；当前架构是 $(uname -m 2>/dev/null || echo unknown)" ;;
esac

install_deps

tmp_parent="${TMPDIR:-}"
if [ -z "$tmp_parent" ]; then
  if [ -n "${PREFIX:-}" ]; then
    tmp_parent="$PREFIX/tmp"
  else
    tmp_parent="$HOME/.cache/tmp"
  fi
fi
mkdir -p "$tmp_parent"
tmp="$tmp_parent/codex-zh-install.$$"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp"

archive_url="$BASE_URL/$ARCHIVE"
cache_dir="$(choose_cache_dir)"
mkdir -p "$cache_dir"
archive_path="$cache_dir/$ARCHIVE"

if [ -f "$archive_path" ]; then
  cached_sha="$(sha256_file "$archive_path" 2>/dev/null || true)"
  if [ "$cached_sha" = "$ARCHIVE_SHA256" ]; then
    info "使用已缓存压缩包: $archive_path"
  else
    warn "缓存压缩包校验失败，将重新下载: $archive_path"
    rm -f "$archive_path"
  fi
fi

if [ ! -f "$archive_path" ]; then
  download_path="$tmp/$ARCHIVE.part"
  info "下载 $archive_url"
  download "$archive_url" "$download_path"

  actual_download_sha="$(sha256_file "$download_path")"
  [ "$actual_download_sha" = "$ARCHIVE_SHA256" ] || die "压缩包 sha256 不匹配: $actual_download_sha"
  mv "$download_path" "$archive_path"
fi

actual_archive_sha="$(sha256_file "$archive_path")"
[ "$actual_archive_sha" = "$ARCHIVE_SHA256" ] || die "压缩包 sha256 不匹配: $actual_archive_sha"

tar -xzf "$archive_path" -C "$tmp"
src="$tmp/codex-${VERSION}-zh-${TARGET}"
[ -f "$src" ] || die "压缩包里没有 codex 二进制"

actual_bin_sha="$(sha256_file "$src")"
[ "$actual_bin_sha" = "$BIN_SHA256" ] || die "二进制 sha256 不匹配: $actual_bin_sha"

install_dir="$(choose_install_dir)"
mkdir -p "$install_dir"
real_path="$install_dir/codex-zh"
target_path="$install_dir/$INSTALL_NAME"

cp "$src" "$real_path"
chmod 755 "$real_path"

if [ "$INSTALL_NAME" != "codex-zh" ]; then
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    current_link="$(readlink "$target_path" 2>/dev/null || true)"
    if [ "$current_link" != "$real_path" ]; then
      backup="$target_path.bak.$(date +%Y%m%d%H%M%S)"
      info "备份已有命令 $target_path 到 $backup"
      mv "$target_path" "$backup"
    fi
  fi
  ln -sf "$real_path" "$target_path" 2>/dev/null || cp "$real_path" "$target_path"
fi

installed_sha="$(sha256_file "$real_path")"
[ "$installed_sha" = "$BIN_SHA256" ] || die "已安装二进制 sha256 不匹配: $installed_sha"

info "已安装: $real_path"
if [ "$INSTALL_NAME" != "codex-zh" ]; then
  info "命令: $target_path"
fi

if [ "$SKIP_RUN" = "1" ]; then
  info "跳过运行检查，因为 CODEX_ZH_SKIP_RUN=1"
  info "完成"
  exit 0
fi

version_check_file="$tmp/version.out"
if "$target_path" --version >"$version_check_file" 2>&1; then
  version_output="$(cat "$version_check_file")"
  info "$version_output"
  info "完成"
else
  status=$?
  warn "已安装，但运行检查失败，退出码 $status"
  cat "$version_check_file" >&2 || true
  exit "$status"
fi
