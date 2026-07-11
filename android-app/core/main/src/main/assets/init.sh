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

ensure_codex_preview() {
  bin_dir="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin"
  mkdir -p "$bin_dir" 2>/dev/null || return 0
  if [ -x "$bin_dir/codex-preview" ]; then
    cat > "$bin_dir/codex-push-image" <<'EOF'
#!/usr/bin/env sh
set -eu
if command -v codex-preview >/dev/null 2>&1; then
  exec codex-preview "$@"
fi
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/codex-preview" "$@"
EOF
    cat > "$bin_dir/codex-push-media" <<'EOF'
#!/usr/bin/env sh
set -eu
if command -v codex-preview >/dev/null 2>&1; then
  exec codex-preview "$@"
fi
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/codex-preview" "$@"
EOF
    chmod 755 "$bin_dir/codex-push-image" "$bin_dir/codex-push-media" 2>/dev/null || true
    return 0
  fi
  cat > "$bin_dir/codex-preview" <<'EOF'
#!/usr/bin/env sh
set -eu

usage() {
  printf '%s\n' "用法: codex-preview [--present|--background] /path/to/image-video-or-text"
  printf '%s\n' "      codex-preview [--present|--background] text --stdin [--name NAME]"
  printf '%s\n' "      codex-preview path FILE_ID"
  printf '%s\n' "      codex-preview status|events|wait|close"
}

find_prefix() {
  if [ -n "${PREFIX:-}" ]; then
    printf '%s\n' "$PREFIX"
    return 0
  fi

  if [ -n "${PKG:-}" ]; then
    if [ -d "/data/user/0/$PKG" ]; then
      printf '%s\n' "/data/user/0/$PKG"
      return 0
    fi
    if [ -d "/data/data/$PKG" ]; then
      printf '%s\n' "/data/data/$PKG"
      return 0
    fi
  fi

  return 1
}

write_clear_request() {
  bridge_dir="$1/local/media-preview"
  request_file="$bridge_dir/request"
  mkdir -p "$bridge_dir"
  {
    printf 'action=clear\n'
    printf 'stamp=%s.%s\n' "$(date +%s 2>/dev/null || printf 0)" "$$"
  } > "$request_file.tmp.$$"
  mv "$request_file.tmp.$$" "$request_file"
  printf '%s\n' "已清空 Codex for TUI 文件面板"
}

write_ref_file() {
  bridge_dir="$1/local/media-preview"
  ref_id="$2"
  path="$3"
  name="$4"
  kind="$5"
  refs_dir="$bridge_dir/refs"
  mkdir -p "$refs_dir"
  {
    printf 'path=%s\n' "$path"
    printf 'name=%s\n' "$name"
    printf 'kind=%s\n' "$kind"
    printf 'stamp=%s\n' "$ref_id"
  } > "$refs_dir/$ref_id.tmp.$$"
  mv "$refs_dir/$ref_id.tmp.$$" "$refs_dir/$ref_id"
}

print_ref_path() {
  bridge_dir="$1/local/media-preview"
  ref_id="$2"
  case "$ref_id" in
    ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
      printf '文件编号无效: %s\n' "$ref_id" >&2
      return 2
      ;;
  esac

  ref_file="$bridge_dir/refs/$ref_id"
  if [ ! -r "$ref_file" ]; then
    printf '找不到文件编号: %s\n' "$ref_id" >&2
    return 1
  fi

  path="$(sed -n 's/^path=//p' "$ref_file" | sed -n '1p')"
  if [ -z "$path" ]; then
    printf '文件编号缺少路径: %s\n' "$ref_id" >&2
    return 1
  fi
  printf '%s\n' "$path"
}

print_file_if_readable() {
  file="$1"
  if [ -r "$file" ]; then
    cat "$file"
    return 0
  fi
  return 1
}

wait_events() {
  panel_dir="$1/local/agent-panel"
  events_file="$panel_dir/events"
  wait_seconds="${CODEX_PREVIEW_WAIT_SECONDS:-120}"
  start_size=0
  [ ! -f "$events_file" ] || start_size="$(wc -c < "$events_file" 2>/dev/null || printf 0)"
  elapsed=0
  while [ "$elapsed" -lt "$wait_seconds" ]; do
    if [ -s "$events_file" ]; then
      size="$(wc -c < "$events_file" 2>/dev/null || printf 0)"
      if [ "$size" != "$start_size" ]; then
        tail -n 40 "$events_file"
        return 0
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  printf '等待文件面板事件超时\n' >&2
  return 1
}

detect_kind() {
  ext="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    jpg|jpeg|png|webp|bmp|gif) printf '%s\n' image ;;
    mp4|m4v|mov|webm|mkv|3gp|avi) printf '%s\n' video ;;
    txt|md|markdown|json|yaml|yml|xml|csv|log) printf '%s\n' text ;;
    *) return 1 ;;
  esac
}

prefix="$(find_prefix)" || {
  printf '%s\n' "找不到 App 数据目录: 请在 Codex for TUI 终端内运行。" >&2
  exit 1
}

[ "$#" -ge 1 ] || { usage >&2; exit 2; }

present=1
case "${1:-}" in
  --background|--collapsed)
    present=0
    shift
    ;;
  --present|--show)
    present=1
    shift
    ;;
esac

[ "$#" -ge 1 ] || { usage >&2; exit 2; }

if [ "$1" = "close" ] || [ "$1" = "--close" ]; then
  write_clear_request "$prefix"
  exit 0
fi

if [ "$1" = "status" ]; then
  print_file_if_readable "$prefix/local/media-preview/status" || print_file_if_readable "$prefix/local/agent-panel/status" || true
  exit 0
fi

if [ "$1" = "events" ]; then
  print_file_if_readable "$prefix/local/agent-panel/events" || true
  exit 0
fi

if [ "$1" = "wait" ]; then
  wait_events "$prefix"
  exit $?
fi

if [ "$#" -eq 2 ] && [ "$1" = "path" ]; then
  print_ref_path "$prefix" "$2"
  exit $?
fi

bridge_dir="$prefix/local/media-preview"
media_dir="$bridge_dir/files"
request_file="$bridge_dir/request"
mkdir -p "$media_dir"

stamp="$(date +%s 2>/dev/null || printf 0).$$"
if [ "$1" = "text" ] && [ "${2:-}" = "--stdin" ]; then
  shift 2
  base="codex-text-$stamp.txt"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        base="$(basename "$2")"
        shift 2
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  done
  ext="txt"
  kind="text"
  dest="$media_dir/$stamp.$ext"
  tmp="$dest.tmp.$$"
  cat > "$tmp"
else
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  src="$1"
  if [ ! -f "$src" ] || [ ! -r "$src" ]; then
    printf '文件不可读: %s\n' "$src" >&2
    exit 1
  fi
  base="$(basename "$src")"
  case "$base" in
    *.*) ext="${base##*.}" ;;
    *) ext="bin" ;;
  esac
  kind="$(detect_kind "$ext")" || {
    printf '暂不支持预览此文件类型: %s\n' "$base" >&2
    exit 2
  }
  dest="$media_dir/$stamp.$ext"
  tmp="$dest.tmp.$$"
  cp "$src" "$tmp"
fi
req_tmp="$request_file.tmp.$$"

mv "$tmp" "$dest"
chmod 600 "$dest" 2>/dev/null || true

{
  printf 'action=show\n'
  printf 'present=%s\n' "$present"
  printf 'kind=%s\n' "$kind"
  printf 'path=%s\n' "$dest"
  printf 'name=%s\n' "$base"
  printf 'stamp=%s\n' "$stamp"
} > "$req_tmp"
mv "$req_tmp" "$request_file"
write_ref_file "$prefix" "$stamp" "$dest" "$base" "$kind"

printf '已发送到 Codex for TUI 文件面板: %s\n' "$base"
EOF
  cat > "$bin_dir/codex-push-image" <<'EOF'
#!/usr/bin/env sh
set -eu
if command -v codex-preview >/dev/null 2>&1; then
  exec codex-preview "$@"
fi
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/codex-preview" "$@"
EOF
  cat > "$bin_dir/codex-push-media" <<'EOF'
#!/usr/bin/env sh
set -eu
if command -v codex-preview >/dev/null 2>&1; then
  exec codex-preview "$@"
fi
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/codex-preview" "$@"
EOF
  chmod 755 "$bin_dir/codex-preview" "$bin_dir/codex-push-image" "$bin_dir/codex-push-media" 2>/dev/null || true
}

# Immediate in-guest feedback as soon as proot hands off to init.
printf '%s\n' "Codex for TUI：环境已就绪，正在初始化…"

ensure_codex_preview
export PATH="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin:$PATH"

# Drop stale test PATH injections that point into deleted cache/tmp trees.
sanitize_profile_d() {
  profile_d="/etc/profile.d/codex-zh.sh"
  [ -f "$profile_d" ] || return 0
  if grep -F 'cache/tmp/codex-tui-static-first-run' "$profile_d" >/dev/null 2>&1 ||
    grep -F 'codex-tui-static-' "$profile_d" >/dev/null 2>&1
  then
    cat >"$profile_d" <<'EOF'
# Managed by Codex for TUI. Keep /usr/local/bin early for codex launcher.
case ":${PATH:-}:" in
  *":/usr/local/bin:"*) ;;
  *) export PATH="/usr/local/bin:${PATH:-}" ;;
esac
EOF
  fi
}

# Hand off to a pure interactive shell after bootstrap guide text.
# Non-interactive `exec /bin/ash` can leave the PTY without echo/icanon on some paths.
# Also install a one-shot interactive rc via ENV so ash re-applies stty after startup.
enter_interactive_shell() {
  # Drop any residual non-interactive flags from bootstrap/upgrade.
  set +e +u +v +x 2>/dev/null || true

  # Visible handoff so "引导结束" is never followed by a silent freeze.
  printf '%s\n' "正在进入交互 shell…"

  # Pure shell home: never leave the user in Codex workspace after guide text.
  # Workspace is still exported for `codex` launcher to avoid project-local config noise.
  if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    cd "$HOME" 2>/dev/null || true
  fi

  # Critical: init-host may route guest stderr through a proot-noise filter.
  # busybox ash writes PS1 (no trailing newline) and CSI 6n to stderr; a line-buffered
  # filter holds them forever, so the session looks stuck after "引导结束" until ^C.
  # Rebind stderr to the session PTY (stdout) before the interactive shell owns the TTY.
  if [ ! -t 2 ] && [ -t 1 ]; then
    exec 2>&1
  fi

  if command -v stty >/dev/null 2>&1; then
    # Prefer the controlling tty when stdin is not already a tty.
    # Never block: only touch stty when the fd is a real tty.
    if [ -t 0 ]; then
      stty sane 2>/dev/null || true
      stty echo icanon icrnl onlcr ixon 2>/dev/null || true
    elif [ -c /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
      # open may fail if no controlling tty; keep it non-fatal and non-blocking.
      stty sane < /dev/tty 2>/dev/null || true
      stty echo icanon icrnl onlcr ixon < /dev/tty 2>/dev/null || true
    fi
  fi

  # ash/bash-compatible interactive startup: re-assert echo once the shell owns the TTY.
  # Keep this rc tiny — large ENV scripts make the post-guide gap feel like a hang.
  shell_rc="${TMPDIR:-/tmp}/codex-for-tui-shell-rc.$$"
  cat >"$shell_rc" <<'EOF' 2>/dev/null || true
# Codex for TUI interactive shell handoff (auto-generated, safe to ignore).
if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
  cd "$HOME" 2>/dev/null || true
fi
if [ ! -t 2 ] && [ -t 1 ]; then
  exec 2>&1
fi
if [ -t 0 ] && command -v stty >/dev/null 2>&1; then
  stty sane 2>/dev/null || true
  stty echo icanon icrnl onlcr ixon 2>/dev/null || true
fi
unset ENV
EOF
  if [ -s "$shell_rc" ]; then
    export ENV="$shell_rc"
  fi

  # Prefer interactive ash so line editing / echo match a normal terminal session.
  # Force unbuffered prompt path: -i is enough; avoid login shell (no second /etc/profile).
  # No extra keypress, no ^C, no exit — guide text ends and shell prompt appears immediately.
  if [ -x /bin/ash ]; then
    exec /bin/ash -i
  fi
  if [ -x /bin/sh ]; then
    exec /bin/sh -i
  fi
  exec /bin/sh
}

if [ "$#" -eq 0 ]; then
  sanitize_profile_d
  [ ! -r /etc/profile ] || . /etc/profile
  export PATH="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin:$PATH"
  # Dedicated workspace is for Codex launches only (see codex-zh-local.sh).
  # Keep the interactive shell at $HOME so normal commands (claude/cloud/etc.) start cleanly.
  workspace="${CODEX_FOR_TUI_WORKSPACE:-$HOME/workspace}"
  mkdir -p "$workspace" 2>/dev/null || true
  export CODEX_FOR_TUI_WORKSPACE="$workspace"
  if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    cd "$HOME" 2>/dev/null || true
  fi
  # Default shell-first; App setting may export CODEX_FOR_TUI_AUTO_START=1.
  export CODEX_FOR_TUI_AUTO_START="${CODEX_FOR_TUI_AUTO_START:-0}"
  bootstrap="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin/codex-for-tui-bootstrap.sh"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "正在准备 python3 依赖…"
    if [ ! -s "$bootstrap" ] ||
      ! HOME=/root CODEX_HOME=/root/.codex sh "$bootstrap" --prepare-apk-upgrade-deps ||
      ! command -v python3 >/dev/null 2>&1
    then
      printf '%s\n' "错误: 无法准备 APK 环境升级所需的 python3，已阻止 Codex 启动。" >&2
      enter_interactive_shell
    fi
  fi
  apk_upgrade="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin/codex-apk-upgrade"
  if [ ! -x "$apk_upgrade" ]; then
    printf '%s\n' "错误: APK 环境升级入口缺失，已阻止 Codex 启动。" >&2
    enter_interactive_shell
  fi
  printf '%s\n' "正在检查环境升级…"
  if ! HOME=/root CODEX_HOME=/root/.codex sh "$apk_upgrade"; then
    printf '%s\n' "错误: APK 环境升级未完成，已回滚并阻止 Codex 启动；下次打开 App 会自动重试。" >&2
    enter_interactive_shell
  fi
  if [ -s "$bootstrap" ]; then
    HOME=/root CODEX_HOME=/root/.codex \
      CODEX_FOR_TUI_AUTO_START="$CODEX_FOR_TUI_AUTO_START" \
      CODEX_FOR_TUI_WORKSPACE="$workspace" \
      sh "$bootstrap" ||
      printf '%s\n' "警告: Codex for TUI 启动引导失败，已回到 shell。" >&2
  fi
  enter_interactive_shell
fi

exec "$@"
