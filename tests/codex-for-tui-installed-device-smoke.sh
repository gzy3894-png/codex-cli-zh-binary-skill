#!/usr/bin/env sh
set -eu

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

info() {
  printf 'INFO: %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

safe_grep() {
  pattern="$1"
  file="$2"
  [ -r "$file" ] || return 1
  grep -F -- "$pattern" "$file" >/dev/null 2>&1
}

assert_contains() {
  haystack="$1"
  needle="$2"
  label="$3"
  printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1 || fail "$label missing: $needle"
}

assert_not_contains() {
  haystack="$1"
  needle="$2"
  label="$3"
  if printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    fail "$label unexpectedly contains: $needle"
  fi
}

find_prefix() {
  if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then
    printf '%s\n' "$PREFIX"
    return 0
  fi
  if [ -n "${PKG:-}" ]; then
    [ -d "/data/user/0/$PKG" ] && { printf '%s\n' "/data/user/0/$PKG"; return 0; }
    [ -d "/data/data/$PKG" ] && { printf '%s\n' "/data/data/$PKG"; return 0; }
  fi
  for package in \
    "${CODEX_TUI_PACKAGE:-}" \
    com.gzy3894.codexfortui \
    com.gzy3894.codexfortui.test
  do
    [ -n "$package" ] || continue
    [ -d "/data/user/0/$package" ] && { printf '%s\n' "/data/user/0/$package"; return 0; }
    [ -d "/data/data/$package" ] && { printf '%s\n' "/data/data/$package"; return 0; }
  done
  return 1
}

wait_file_contains() {
  file="$1"
  needle="$2"
  label="$3"
  wait_seconds="${CODEX_TUI_INSTALLED_WAIT_SECONDS:-20}"
  elapsed=0
  while [ "$elapsed" -lt "$wait_seconds" ]; do
    if safe_grep "$needle" "$file"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  [ ! -r "$file" ] || sed -n '1,120p' "$file" >&2 || true
  fail "$label did not contain '$needle' within ${wait_seconds}s"
}

write_tiny_png() {
  out="$1"
  if command -v base64 >/dev/null 2>&1; then
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=' | base64 -d > "$out"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$out" <<'PY'
import base64, sys
open(sys.argv[1], "wb").write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
PY
  else
    fail "missing base64 or python3 to create png fixture"
  fi
}

prefix="$(find_prefix)" || fail "cannot find Codex for TUI app data dir"
package="${CODEX_TUI_PACKAGE:-${PKG:-$(basename "$prefix")}}"
export PREFIX="$prefix"
export PATH="$prefix/local/bin:$PATH"

printf 'Codex for TUI installed device smoke\n'
printf 'package=%s\n' "$package"
printf 'prefix=%s\n' "$prefix"

for cmd in \
  codex codex-update codex-local codex-browser codex-preview codex-panel \
  codex-session codex-rtk codex-context
do
  need_cmd "$cmd"
  printf 'cmd_%s=%s\n' "$cmd" "$(command -v "$cmd")"
done

if command -v pm >/dev/null 2>&1; then
  pm_line="$(pm list packages --show-versioncode "$package" 2>/dev/null | sed -n '1p' || true)"
  [ -n "$pm_line" ] || fail "pm cannot find package: $package"
  printf 'pm=%s\n' "$pm_line"
  if [ -n "${CODEX_TUI_EXPECTED_VERSION_CODE:-}" ]; then
    assert_contains "$pm_line" "versionCode:${CODEX_TUI_EXPECTED_VERSION_CODE}" "pm version"
  fi
fi

if [ -s "$HOME/.codex/config.toml" ]; then
  if safe_grep "可用模型" "$HOME/.codex/config.toml"; then
    fail "config.toml model field appears polluted by menu text"
  fi
  printf 'config_present=1\n'
else
  warn "config.toml not present; skipping config pollution check"
fi

rtk_status="$(codex-rtk status 2>&1)" || fail "codex-rtk status failed"
printf '%s\n' "$rtk_status" | sed -n '1,12p'
assert_contains "$rtk_status" "rtk_path=" "rtk status"
assert_contains "$rtk_status" "hooks_feature=true" "rtk status"

context_status="$(codex-context status 2>&1)" || fail "codex-context status failed"
printf '%s\n' "$context_status" | sed -n '1,14p'
assert_contains "$context_status" "context_hook=" "context status"
assert_contains "$context_status" "hooks_feature=true" "context status"

if [ "${CODEX_TUI_REQUIRE_HOOKS:-0}" = "1" ]; then
  assert_contains "$rtk_status" "rtk_hook=enabled" "rtk hook"
  assert_contains "$rtk_status" "rtk_hook_source=requirements" "rtk hook source"
  assert_contains "$context_status" "context_hook=enabled" "context hook"
  assert_contains "$context_status" "context_hook_source=requirements" "context hook source"
fi

tmp="${TMPDIR:-/tmp}/codex-tui-installed-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

png="$tmp/tiny.png"
write_tiny_png "$png"

codex-preview clear installed_smoke_clear >/dev/null
image_output="$(codex-preview --background "$png" 2>&1)" || fail "codex-preview image failed"
assert_contains "$image_output" "已发送到 Codex for TUI 文件面板" "image preview output"
request_file="$prefix/local/media-preview/request"
wait_file_contains "$request_file" "kind=image" "media-preview request"
wait_file_contains "$request_file" "present=0" "media-preview request"
image_id="$(sed -n 's/^stamp=//p' "$request_file" | sed -n '1p')"
[ -n "$image_id" ] || fail "image preview request missing stamp"
image_path="$(codex-preview path "$image_id")" || fail "codex-preview path failed for image"
[ -s "$image_path" ] || fail "resolved image preview path is empty: $image_path"
printf 'preview_image_id=%s\n' "$image_id"

long_text="installed smoke long text line 1
installed smoke long text line 2"
text_output="$(printf '%s\n' "$long_text" | codex-preview --background text --stdin --name installed-smoke.txt 2>&1)" || fail "codex-preview stdin text failed"
assert_contains "$text_output" "已发送到 Codex for TUI 文件面板" "text preview output"
assert_not_contains "$text_output" "installed smoke long text" "text preview output"
wait_file_contains "$request_file" "kind=text" "media-preview text request"
text_id="$(sed -n 's/^stamp=//p' "$request_file" | sed -n '1p')"
[ -n "$text_id" ] || fail "text preview request missing stamp"
text_path="$(codex-preview path "$text_id")" || fail "codex-preview path failed for text"
[ -s "$text_path" ] || fail "resolved text preview path is empty: $text_path"
printf 'preview_text_id=%s\n' "$text_id"

if [ -n "${CODEX_TUI_SMOKE_VIDEO_PATH:-}" ]; then
  [ -r "$CODEX_TUI_SMOKE_VIDEO_PATH" ] || fail "CODEX_TUI_SMOKE_VIDEO_PATH is not readable"
  video_output="$(codex-preview --background "$CODEX_TUI_SMOKE_VIDEO_PATH" 2>&1)" || fail "codex-preview video failed"
  assert_contains "$video_output" "已发送到 Codex for TUI 文件面板" "video preview output"
  wait_file_contains "$request_file" "kind=video" "media-preview video request"
  video_id="$(sed -n 's/^stamp=//p' "$request_file" | sed -n '1p')"
  printf 'preview_video_id=%s\n' "$video_id"
else
  warn "CODEX_TUI_SMOKE_VIDEO_PATH not set; skipping real video preview"
fi

codex-panel collapse files installed_smoke_collapse >/dev/null
codex-panel status files >/dev/null || fail "codex-panel status files failed"
codex-panel events >/dev/null || fail "codex-panel events failed"

run_id="installed-smoke-$$"
codex-session start --run "$run_id" "Installed smoke" >/dev/null
printf 'session body\n' | codex-session add text --run "$run_id" --stdin --title "Smoke text" >/dev/null
codex-session done "$run_id" "ok" >/dev/null
codex-session timeline collapse installed_smoke >/dev/null
codex-session status >/dev/null || fail "codex-session status failed"

perf_file="$prefix/local/perf/terminal.status"
if [ -r "$perf_file" ]; then
  assert_contains "$(sed -n '1,80p' "$perf_file")" "render_requests=" "terminal perf status"
  printf 'perf_status=%s\n' "$perf_file"
else
  warn "terminal perf status not readable yet: $perf_file"
fi

if [ "${CODEX_TUI_SKIP_BROWSER:-0}" != "1" ]; then
  browser_open="$(codex-browser open https://example.com 2>&1)" || fail "codex-browser open failed"
  assert_contains "$browser_open" "state=done" "browser open"
  js_output="$(codex-browser js "document.title" 2>&1)" || fail "codex-browser js failed"
  js_request="$(printf '%s\n' "$js_output" | sed -n 's/^request_id=//p' | sed -n '1p')"
  [ -n "$js_request" ] || fail "browser js request id missing"
  js_result="$(codex-browser result "$js_request" 2>&1)" || fail "browser js result failed"
  assert_contains "$js_result" '"value": "Example Domain"' "browser js result"
  codex-browser collapse installed_smoke_browser >/dev/null
  screenshot_output="$(codex-browser screenshot --push --background 2>&1)" || fail "browser background screenshot failed"
  assert_contains "$screenshot_output" "file_id=" "browser screenshot"
  browser_status="$(codex-browser status 2>&1)" || fail "browser status failed"
  assert_contains "$browser_status" "visible=0" "browser collapsed screenshot status"
  assert_contains "$browser_status" "collapsed=1" "browser collapsed screenshot status"
  auth_output="$(codex-browser auth-open --reason installed_smoke https://example.com 2>&1)" || fail "browser auth-open failed"
  auth_id="$(printf '%s\n' "$auth_output" | sed -n 's/^auth_request_id=//p' | sed -n '1p')"
  [ -n "$auth_id" ] || fail "auth-open missing auth_request_id"
  codex-browser auth-cancel "$auth_id" >/dev/null || fail "auth-cancel failed"
  after_auth="$(codex-browser open https://example.com 2>&1)" || fail "browser open after auth-cancel failed"
  assert_contains "$after_auth" "state=done" "browser open after auth-cancel"
  assert_not_contains "$after_auth" "user_action=cancel" "browser open after auth-cancel"
fi

printf 'OK: Codex for TUI installed device smoke passed\n'
