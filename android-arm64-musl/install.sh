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

info() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
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
  die "missing sha256sum or openssl"
}

install_deps() {
  if [ "$SKIP_DEPS" = "1" ]; then
    info "skip dependency install because CODEX_ZH_SKIP_DEPS=1"
    return
  fi

  if have pkg && [ -n "${PREFIX:-}" ]; then
    info "installing Termux dependencies..."
    pkg update -y
    pkg install -y ca-certificates curl tar gzip git openssh ripgrep jq
    pkg install -y fd >/dev/null 2>&1 || true
    return
  fi

  if have apt-get; then
    info "installing Debian/Ubuntu dependencies..."
    if [ "$(id -u)" = "0" ]; then
      APT="apt-get"
    elif have sudo; then
      APT="sudo apt-get"
    else
      warn "apt-get found but sudo/root unavailable; skipping dependency install"
      return
    fi
    $APT update
    $APT install -y ca-certificates curl tar gzip git openssh-client ripgrep jq
    return
  fi

  if have apk; then
    info "installing Alpine dependencies..."
    if [ "$(id -u)" = "0" ]; then
      apk add --no-cache ca-certificates curl tar gzip git openssh-client ripgrep fd jq
    elif have sudo; then
      sudo apk add --no-cache ca-certificates curl tar gzip git openssh-client ripgrep fd jq
    else
      warn "apk found but sudo/root unavailable; skipping dependency install"
    fi
    return
  fi

  warn "no supported package manager found; continuing without dependency install"
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
  die "missing curl or wget"
}

case "$(uname -m 2>/dev/null || true)" in
  aarch64|arm64) ;;
  *) warn "this package is built for Android/Linux ARM64; current arch is $(uname -m 2>/dev/null || echo unknown)" ;;
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

archive_path="$tmp/$ARCHIVE"
archive_url="$BASE_URL/$ARCHIVE"
info "downloading $archive_url"
download "$archive_url" "$archive_path"

actual_archive_sha="$(sha256_file "$archive_path")"
[ "$actual_archive_sha" = "$ARCHIVE_SHA256" ] || die "archive sha256 mismatch: $actual_archive_sha"

tar -xzf "$archive_path" -C "$tmp"
src="$tmp/codex-${VERSION}-zh-${TARGET}"
[ -f "$src" ] || die "archive did not contain codex binary"

actual_bin_sha="$(sha256_file "$src")"
[ "$actual_bin_sha" = "$BIN_SHA256" ] || die "binary sha256 mismatch: $actual_bin_sha"

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
      info "backing up existing $target_path to $backup"
      mv "$target_path" "$backup"
    fi
  fi
  ln -sf "$real_path" "$target_path" 2>/dev/null || cp "$real_path" "$target_path"
fi

installed_sha="$(sha256_file "$real_path")"
[ "$installed_sha" = "$BIN_SHA256" ] || die "installed binary sha256 mismatch: $installed_sha"

info "installed: $real_path"
if [ "$INSTALL_NAME" != "codex-zh" ]; then
  info "command: $target_path"
fi

if [ "$SKIP_RUN" = "1" ]; then
  info "skip runtime check because CODEX_ZH_SKIP_RUN=1"
  info "done"
  exit 0
fi

version_check_file="$tmp/version.out"
if "$target_path" --version >"$version_check_file" 2>&1; then
  version_output="$(cat "$version_check_file")"
  info "$version_output"
  info "done"
else
  status=$?
  warn "installed, but runtime check failed with exit code $status"
  cat "$version_check_file" >&2 || true
  exit "$status"
fi
