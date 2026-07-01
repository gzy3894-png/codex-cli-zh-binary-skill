#!/system/bin/sh
set -e

PREFIX="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}"
ALPINE_DIR="$PREFIX/local/alpine"
ALPINE_TARBALL="$PREFIX/files/alpine.tar.gz"

mkdir -p "$ALPINE_DIR"

if [ -f "$ALPINE_TARBALL" ] && [ -z "$(find "$ALPINE_DIR" -mindepth 1 -maxdepth 1 ! -name root ! -name tmp 2>/dev/null | sed -n '1p')" ]; then
  tar -xf "$ALPINE_TARBALL" -C "$ALPINE_DIR"
fi

add_bind() {
  src="$1"
  dst="${2:-}"
  [ -e "$src" ] || return 0
  if command -v realpath >/dev/null 2>&1; then
    src="$(realpath "$src" 2>/dev/null || printf '%s' "$src")"
  fi
  if [ -n "$dst" ]; then
    ARGS="$ARGS -b $src:$dst"
  else
    ARGS="$ARGS -b $src"
  fi
}

ARGS="--kill-on-exit -w /"

for path in \
  /apex /odm /product /system /system_ext /vendor \
  /linkerconfig/ld.config.txt \
  /linkerconfig/com.android.art/ld.config.txt \
  /plat_property_contexts /property_contexts
do
  add_bind "$path"
done

add_bind /sdcard
add_bind /storage
add_bind /dev
add_bind /data
add_bind /dev/urandom /dev/random
add_bind /proc
add_bind "$PREFIX"
add_bind "$PREFIX/local/stat" /proc/stat
add_bind "$PREFIX/local/vmstat" /proc/vmstat
add_bind /proc/self/fd /dev/fd
add_bind /proc/self/fd/0 /dev/stdin
add_bind /proc/self/fd/1 /dev/stdout
add_bind /proc/self/fd/2 /dev/stderr
add_bind /sys

mkdir -p "$ALPINE_DIR/tmp"
chmod 1777 "$ALPINE_DIR/tmp" 2>/dev/null || true
ARGS="$ARGS -b $ALPINE_DIR/tmp:/dev/shm"
ARGS="$ARGS -r $ALPINE_DIR -0 --link2symlink --sysvipc -L"

exec "$PROOT" $ARGS sh "$PREFIX/local/bin/init" "$@"
