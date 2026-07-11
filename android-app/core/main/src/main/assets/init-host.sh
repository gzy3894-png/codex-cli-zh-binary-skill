#!/system/bin/sh
set -e

PREFIX="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}"
ALPINE_DIR="$PREFIX/local/alpine"
ALPINE_TARBALL="$PREFIX/files/alpine.tar.gz"
ROOTFS_READY_MARKER=".codex-rootfs-ready"
ROOTFS_LOCK="$PREFIX/local/alpine.install.lock"
ROOTFS_WAIT_SECONDS="${ROOTFS_WAIT_SECONDS:-120}"

# Immediate feedback before any rootfs/proot work so the terminal is never blank.
# Use stderr so the line is less likely to be swallowed by later filters.
printf '%s\n' "Codex for TUI：正在启动…" >&2

rootfs_has_payload() {
  [ -d "$ALPINE_DIR" ] || return 1
  [ -n "$(find "$ALPINE_DIR" -mindepth 1 -maxdepth 1 ! -name root ! -name tmp ! -name "$ROOTFS_READY_MARKER" 2>/dev/null | sed -n '1p')" ]
}

rootfs_mark_ready() {
  mkdir -p "$ALPINE_DIR"
  printf 'ready %s\n' "$(date '+%s' 2>/dev/null || printf unknown)" > "$ALPINE_DIR/$ROOTFS_READY_MARKER"
}

rootfs_ready() {
  [ -f "$ALPINE_DIR/$ROOTFS_READY_MARKER" ] && rootfs_has_payload
}

wait_for_rootfs_ready() {
  waited=0
  while [ "$waited" -lt "$ROOTFS_WAIT_SECONDS" ]; do
    if rootfs_ready; then
      return 0
    fi
    if rootfs_has_payload; then
      rootfs_mark_ready
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

cleanup_rootfs_install() {
  [ -n "${ROOTFS_EXTRACT_DIR:-}" ] && rm -rf "$ROOTFS_EXTRACT_DIR"
  [ -n "${ROOTFS_LOCK_HELD:-}" ] && rmdir "$ROOTFS_LOCK" 2>/dev/null || true
}

install_rootfs_if_needed() {
  if rootfs_ready; then
    return 0
  fi
  if rootfs_has_payload; then
    rootfs_mark_ready
    return 0
  fi

  [ -f "$ALPINE_TARBALL" ] || {
    echo "Missing Alpine rootfs archive: $ALPINE_TARBALL" >&2
    exit 1
  }

  mkdir -p "$PREFIX/local"
  if mkdir "$ROOTFS_LOCK" 2>/dev/null; then
    ROOTFS_LOCK_HELD=1
    ROOTFS_EXTRACT_DIR="$PREFIX/local/alpine.extracting.$$"
    ROOTFS_OLD_DIR="$PREFIX/local/alpine.previous.$$"
    trap cleanup_rootfs_install EXIT
    trap 'cleanup_rootfs_install; exit 1' HUP INT TERM

    if rootfs_ready; then
      cleanup_rootfs_install
      ROOTFS_LOCK_HELD=
      ROOTFS_EXTRACT_DIR=
      ROOTFS_OLD_DIR=
      trap - EXIT HUP INT TERM
      return 0
    fi

    rm -rf "$ROOTFS_EXTRACT_DIR" "$ROOTFS_OLD_DIR"
    mkdir -p "$ROOTFS_EXTRACT_DIR"
    tar -xf "$ALPINE_TARBALL" -C "$ROOTFS_EXTRACT_DIR"
    mkdir -p "$ROOTFS_EXTRACT_DIR/tmp"
    chmod 1777 "$ROOTFS_EXTRACT_DIR/tmp" 2>/dev/null || true
    printf 'ready %s\n' "$(date '+%s' 2>/dev/null || printf unknown)" > "$ROOTFS_EXTRACT_DIR/$ROOTFS_READY_MARKER"

    if [ -d "$ALPINE_DIR" ]; then
      if ! mv "$ALPINE_DIR" "$ROOTFS_OLD_DIR"; then
        echo "Unable to stage previous Alpine rootfs: $ALPINE_DIR" >&2
        exit 1
      fi
    fi
    if ! mv "$ROOTFS_EXTRACT_DIR" "$ALPINE_DIR"; then
      if [ -d "$ROOTFS_OLD_DIR" ]; then
        mv "$ROOTFS_OLD_DIR" "$ALPINE_DIR" 2>/dev/null || true
      fi
      echo "Unable to activate new Alpine rootfs: $ALPINE_DIR" >&2
      exit 1
    fi
    if [ -d "$ROOTFS_OLD_DIR/root" ] && [ -d "$ALPINE_DIR/root" ]; then
      cp -a "$ROOTFS_OLD_DIR/root/." "$ALPINE_DIR/root/" 2>/dev/null || true
    fi
    rm -rf "$ROOTFS_OLD_DIR"
    rmdir "$ROOTFS_LOCK" 2>/dev/null || true

    ROOTFS_LOCK_HELD=
    ROOTFS_EXTRACT_DIR=
    ROOTFS_OLD_DIR=
    trap - EXIT HUP INT TERM
  else
    wait_for_rootfs_ready || {
      echo "Timed out waiting for Alpine rootfs install lock: $ROOTFS_LOCK" >&2
      exit 1
    }
  fi
}

install_rootfs_if_needed

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

# proot needs a writable private tmp; fall back if session env was wiped/missing.
if [ -z "${PROOT_TMP_DIR:-}" ] || ! mkdir -p "$PROOT_TMP_DIR" 2>/dev/null; then
  PROOT_TMP_DIR="${PREFIX:-/data/data/com.gzy3894.codexfortui}/local/proot-tmp/$$"
  export PROOT_TMP_DIR
  mkdir -p "$PROOT_TMP_DIR" 2>/dev/null || true
fi

# Filter known-harmless proot noise that otherwise corrupts TUI/shell output.
# Keep stdout on the session PTY; only route stderr through a line filter.
# Codex TUI uses the tty/stdout path, so this does not break the interface.
if [ "${CODEX_FOR_TUI_FILTER_PROOT_WARNINGS:-1}" = "1" ] &&
  [ -n "${PROOT_TMP_DIR:-}" ] &&
  mkdir -p "$PROOT_TMP_DIR" 2>/dev/null
then
  fifo="$PROOT_TMP_DIR/proot-err.$$"
  rm -f "$fifo"
  if mkfifo "$fifo" 2>/dev/null; then
    (
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
          *"proot warning: can't sanitize binding"*) ;;
          *"proot warning: can"*"t sanitize binding"*) ;;
          *"proot warning: ptrace("*) ;;
          *"proot warning: can't set tracee registers"*) ;;
          *"proot warning: can"*"t set tracee registers"*) ;;
          *"proot info: Please set PROOT_TMP_DIR"*) ;;
          *"Please set PROOT_TMP_DIR env"*) ;;
          *) printf '%s\n' "$line" ;;
        esac
      done < "$fifo" >&2
    ) &
    filter_pid=$!
    set +e
    # shellcheck disable=SC2086
    "$PROOT" $ARGS sh "$PREFIX/local/bin/init" "$@" 2>"$fifo"
    rc=$?
    set -e
    wait "$filter_pid" 2>/dev/null || true
    rm -f "$fifo"
    exit "$rc"
  fi
fi

# shellcheck disable=SC2086
exec "$PROOT" $ARGS sh "$PREFIX/local/bin/init" "$@"
