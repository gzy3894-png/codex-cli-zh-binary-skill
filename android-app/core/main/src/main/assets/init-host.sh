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
    # A force-stopped first install cannot run its EXIT trap. Recover its
    # legacy empty lock (or a lock whose recorded process is no longer alive)
    # after a short grace period, then let the caller retry atomically.
    if clear_stale_rootfs_lock "$waited"; then
      return 2
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

process_start_token() {
  awk '{print $22}' "/proc/$1/stat" 2>/dev/null || true
}

clear_stale_rootfs_lock() {
  stale_waited="$1"
  [ "$stale_waited" -ge 2 ] || return 1

  holder="$(sed -n '1p' "$ROOTFS_LOCK/pid" 2>/dev/null || true)"
  case "$holder" in
    ""|*[!0-9]*) holder="" ;;
  esac
  holder_start="$(sed -n '1p' "$ROOTFS_LOCK/start" 2>/dev/null || true)"
  current_start=""
  [ -z "$holder" ] || current_start="$(process_start_token "$holder")"
  if [ -n "$holder" ] &&
    kill -0 "$holder" 2>/dev/null &&
    [ -n "$holder_start" ] &&
    [ "$holder_start" = "$current_start" ]
  then
    return 1
  fi

  rm -f "$ROOTFS_LOCK/pid" "$ROOTFS_LOCK/start" 2>/dev/null || true
  rmdir "$ROOTFS_LOCK" 2>/dev/null || return 1
  rm -rf "$PREFIX"/local/alpine.extracting.*
  return 0
}

cleanup_rootfs_install() {
  [ -n "${ROOTFS_EXTRACT_DIR:-}" ] && rm -rf "$ROOTFS_EXTRACT_DIR"
  if [ -n "${ROOTFS_LOCK_HELD:-}" ]; then
    rm -f "$ROOTFS_LOCK/pid" "$ROOTFS_LOCK/start" 2>/dev/null || true
    rmdir "$ROOTFS_LOCK" 2>/dev/null || true
  fi
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
    printf '%s\n' "$$" > "$ROOTFS_LOCK/pid"
    printf '%s\n' "$(process_start_token "$$")" > "$ROOTFS_LOCK/start"
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
    # Android's Toybox tar restores archived uid/gid by default. App processes
    # cannot chown files to root:root, so a first install otherwise ends with
    # "chown 0:0: Operation not permitted".  -o means "ignore owner" for both
    # Toybox tar and GNU tar; ownership stays with the app sandbox user.
    tar -oxf "$ALPINE_TARBALL" -C "$ROOTFS_EXTRACT_DIR"
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
    rm -f "$ROOTFS_LOCK/pid" "$ROOTFS_LOCK/start" 2>/dev/null || true
    rmdir "$ROOTFS_LOCK" 2>/dev/null || true

    ROOTFS_LOCK_HELD=
    ROOTFS_EXTRACT_DIR=
    ROOTFS_OLD_DIR=
    trap - EXIT HUP INT TERM
  else
    if wait_for_rootfs_ready; then
      :
    else
      wait_rc=$?
      if [ "$wait_rc" -eq 2 ]; then
        install_rootfs_if_needed
        return
      fi
      echo "Timed out waiting for Alpine rootfs install lock: $ROOTFS_LOCK" >&2
      exit 1
    fi
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
# Keep stdout on the session PTY; only route stderr through a noise filter.
# Codex TUI uses the tty/stdout path, so this does not break the interface.
#
# IMPORTANT: must be byte-wise / prefix-aware, NOT line-buffered.
# busybox ash writes PS1 without a trailing newline (and may emit CSI 6n).
# A plain `read -r line` holds that prompt forever → looks like "卡在引导".
if [ "${CODEX_FOR_TUI_FILTER_PROOT_WARNINGS:-1}" = "1" ] &&
  [ -n "${PROOT_TMP_DIR:-}" ] &&
  mkdir -p "$PROOT_TMP_DIR" 2>/dev/null
then
  fifo="$PROOT_TMP_DIR/proot-err.$$"
  rm -f "$fifo"
  if mkfifo "$fifo" 2>/dev/null; then
    (
      is_proot_noise_line() {
        case "$1" in
          *"proot warning: can't sanitize binding"*) return 0 ;;
          *"proot warning: can"*"t sanitize binding"*) return 0 ;;
          *"proot warning: ptrace("*) return 0 ;;
          *"proot warning: can't set tracee registers"*) return 0 ;;
          *"proot warning: can"*"t set tracee registers"*) return 0 ;;
          *"proot info: Please set PROOT_TMP_DIR"*) return 0 ;;
          *"Please set PROOT_TMP_DIR env"*) return 0 ;;
          *) return 1 ;;
        esac
      }

      # Hold only while buf is still a prefix of a known noise pattern.
      # Anything else (shell prompts, CSI, normal logs) is flushed immediately.
      could_become_proot_noise() {
        case "$1" in
          ''|p|pr|pro|proo|proot|proot\ |proot\ w*|proot\ i*|P|Pl|Ple|Plea|Pleas|Please|Please\ *)
            return 0
            ;;
          *)
            return 1
            ;;
        esac
      }

      # Byte-wise filter: Android /system/bin/sh supports `read -n 1`.
      # Do not use line-buffered `read -r line` — ash PS1 has no trailing newline.
      buf=""
      while IFS= read -r -n 1 c; do
        buf="${buf}${c}"
        case "$c" in
          '
')
            if ! is_proot_noise_line "$buf"; then
              printf '%s' "$buf"
            fi
            buf=""
            ;;
          *)
            if ! could_become_proot_noise "$buf"; then
              printf '%s' "$buf"
              buf=""
            fi
            ;;
        esac
      done
      if [ -n "$buf" ] && ! is_proot_noise_line "$buf"; then
        printf '%s' "$buf"
      fi
    ) < "$fifo" >&2 &
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
