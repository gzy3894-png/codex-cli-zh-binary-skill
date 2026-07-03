#!/usr/bin/env sh
set -e

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/system/bin:/system/xbin:${PATH:-}
export HOME="${HOME:-/root}"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export PIP_BREAK_SYSTEM_PACKAGES=1
export PS1='\[\033[01;32m\]\u@codex-tui\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

if [ ! -s /etc/resolv.conf ]; then
  echo "nameserver 8.8.8.8" > /etc/resolv.conf 2>/dev/null || true
fi

if [ ! -f /linkerconfig/ld.config.txt ]; then
  mkdir -p /linkerconfig 2>/dev/null || true
  if [ -d /linkerconfig ]; then
    : > /linkerconfig/ld.config.txt 2>/dev/null || true
  fi
fi

ensure_codex_push_image() {
  bin_dir="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin"
  mkdir -p "$bin_dir" 2>/dev/null || return 0
  cat > "$bin_dir/codex-push-image" <<'EOF'
#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  printf '%s\n' "用法: codex-push-image /path/to/image" >&2
  exit 2
fi

src="$1"
if [ ! -f "$src" ] || [ ! -r "$src" ]; then
  printf '图片不可读: %s\n' "$src" >&2
  exit 1
fi

prefix="${PREFIX:-}"
if [ -z "$prefix" ] && [ -n "${PKG:-}" ]; then
  if [ -d "/data/user/0/$PKG" ]; then
    prefix="/data/user/0/$PKG"
  elif [ -d "/data/data/$PKG" ]; then
    prefix="/data/data/$PKG"
  fi
fi

if [ -z "$prefix" ]; then
  printf '%s\n' "找不到 App 数据目录: 请在 Codex for TUI 终端内运行。" >&2
  exit 1
fi

bridge_dir="$prefix/local/image-preview"
image_dir="$bridge_dir/images"
request_file="$bridge_dir/request"
mkdir -p "$image_dir"

base="$(basename "$src")"
case "$base" in
  *.*) ext=".${base##*.}" ;;
  *) ext=".img" ;;
esac

dest="$image_dir/latest$ext"
tmp="$dest.tmp.$$"
req_tmp="$request_file.tmp.$$"

cp "$src" "$tmp"
mv "$tmp" "$dest"
chmod 600 "$dest" 2>/dev/null || true

{
  printf 'path=%s\n' "$dest"
  printf 'name=%s\n' "$base"
  printf 'stamp=%s.%s\n' "$(date +%s 2>/dev/null || printf 0)" "$$"
} > "$req_tmp"
mv "$req_tmp" "$request_file"

printf '已发送到 Codex for TUI 图片预览: %s\n' "$src"
EOF
  chmod 755 "$bin_dir/codex-push-image" 2>/dev/null || true
}

ensure_codex_push_image
export PATH="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin:$PATH"

if [ "$#" -eq 0 ]; then
  [ ! -r /etc/profile ] || . /etc/profile
  cd "$HOME" 2>/dev/null || true
  if [ -s "${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin/codex-for-tui-bootstrap.sh" ]; then
    sh "${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin/codex-for-tui-bootstrap.sh" || echo "警告: Codex for TUI 启动失败，已回到 shell。"
  fi
  exec /bin/ash
fi

exec "$@"
