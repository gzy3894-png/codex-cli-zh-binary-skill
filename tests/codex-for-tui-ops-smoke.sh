#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/android-app/core/main/src/main/assets"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "expected pattern not found in $file"
}

assert_not_leaked() {
  label="$1"
  file="$2"
  for needle in "$SECRET_API_KEY" "$SECRET_BEARER" "$SECRET_COOKIE" "$SECRET_REFRESH" "$SECRET_QUERY"; do
    [ -n "$needle" ] || continue
    if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
      fail "$label leaked a sensitive value"
    fi
  done
}

copy_tool() {
  tool="$1"
  src="$ASSET_DIR/$tool"
  [ -s "$src" ] || fail "missing tool asset: $src"
  cp "$src" "$tmp/bin/$tool"
  chmod 755 "$tmp/bin/$tool"
  sh -n "$tmp/bin/$tool" || fail "$tool shell syntax failed"
}

try_capture() {
  label="$1"
  shift
  out="$tmp/out/$label.out"
  err="$tmp/out/$label.err"
  if "$@" >"$out" 2>"$err" </dev/null; then
    assert_not_leaked "$label stdout" "$out"
    assert_not_leaked "$label stderr" "$err"
    return 0
  fi
  assert_not_leaked "$label stdout" "$out"
  assert_not_leaked "$label stderr" "$err"
  return 1
}

run_capture() {
  label="$1"
  shift
  try_capture "$label" "$@" || fail "command failed: $label"
}

find_trash_copy() {
  name="$1"
  find "$tmp" -type f -name "$name" 2>/dev/null | awk '/\/trash\// { print; exit }'
}

tmp="${TMPDIR:-/tmp}/codex-tui-ops-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/out" "$tmp/home/.codex" \
  "$tmp/prefix/local/media-preview/files" \
  "$tmp/prefix/local/media-preview/refs" \
  "$tmp/prefix/local/browser/request-results" \
  "$tmp/prefix/local/browser/screenshots" \
  "$tmp/prefix/local/browser" \
  "$tmp/prefix/local/ops"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

SECRET_API_KEY="sk-worker-d-do-not-print"
SECRET_BEARER="worker-d-bearer-token"
SECRET_COOKIE="worker-d-session-cookie"
SECRET_REFRESH="worker-d-refresh-token"
SECRET_QUERY="worker-d-query-token"

copy_tool codex-doctor
copy_tool codex-clean
copy_tool codex-ops
copy_tool codex-ops-lib

export HOME="$tmp/home"
export CODEX_HOME="$tmp/home/.codex"
export PREFIX="$tmp/prefix"
export PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}"
export CODEX_CLEAN_ASSUME_YES=1
export CODEX_CLEAN_MIN_AGE_SECONDS=0
export CODEX_TUI_CLEAN_TEST=1

cat > "$CODEX_HOME/auth.json" <<EOF
{
  "OPENAI_API_KEY": "$SECRET_API_KEY",
  "refresh_token": "$SECRET_REFRESH"
}
EOF

cat > "$CODEX_HOME/config.toml" <<EOF
model_provider = "custom"
model = "worker-d-model"

[model_providers.custom]
base_url = "https://api.example.test/v1?api_key=$SECRET_QUERY"
wire_api = "responses"
EOF

cat > "$PREFIX/local/browser/status" <<EOF
url=https://example.test/callback?access_token=$SECRET_QUERY
authorization=Bearer $SECRET_BEARER
cookie=$SECRET_COOKIE
EOF

cat > "$PREFIX/local/browser/events" <<EOF
{"kind":"auth","token":"$SECRET_BEARER","cookie":"$SECRET_COOKIE"}
EOF

cat > "$PREFIX/local/ops/status" <<EOF
state=running
api_key=$SECRET_API_KEY
authorization=Bearer $SECRET_BEARER
EOF

cat > "$PREFIX/local/ops/events" <<EOF
{"kind":"resume","refresh_token":"$SECRET_REFRESH"}
EOF

cat > "$PREFIX/local/ops/resume_hint" <<EOF
上次任务可恢复；不要输出 token=$SECRET_QUERY 或 cookie=$SECRET_COOKIE
EOF

clean_target="$PREFIX/local/media-preview/files/worker-d-clean-target.txt"
clean_ref="$PREFIX/local/media-preview/refs/worker-d-clean-target"
clean_result="$PREFIX/local/browser/request-results/worker-d-result.json"
clean_screenshot="$PREFIX/local/browser/screenshots/worker-d-shot.png"
clean_marker="worker-d-clean-marker"
printf '%s\n' "$clean_marker" > "$clean_target"
printf 'path=%s\nkind=text\nstamp=worker-d-clean-target\n' "$clean_target" > "$clean_ref"
printf '{"marker":"%s"}\n' "$clean_marker" > "$clean_result"
printf 'png:%s\n' "$clean_marker" > "$clean_screenshot"
touch -t 202001010000 "$clean_target" "$clean_ref" "$clean_result" "$clean_screenshot" 2>/dev/null || true

run_capture doctor_default codex-doctor

run_capture ops_status codex-ops status
run_capture ops_events codex-ops events
run_capture ops_resume_hint codex-ops resume_hint

run_capture clean_scan codex-clean scan
[ -s "$clean_target" ] || fail "codex-clean scan removed media-preview file"
[ -s "$clean_ref" ] || fail "codex-clean scan removed media-preview ref"
[ -s "$clean_result" ] || fail "codex-clean scan removed browser result file"
[ -s "$clean_screenshot" ] || fail "codex-clean scan removed browser screenshot"
[ -s "$CODEX_HOME/auth.json" ] || fail "codex-clean scan touched auth.json"

run_capture clean_apply codex-clean apply --yes --all
[ ! -e "$clean_target" ] || fail "codex-clean apply should move media-preview file out of its original location"
[ ! -e "$clean_ref" ] || fail "codex-clean apply should move media-preview ref out of its original location"
[ ! -e "$clean_result" ] || fail "codex-clean apply should move browser result file out of its original location"
[ ! -e "$clean_screenshot" ] || fail "codex-clean apply should move browser screenshot out of its original location"
[ -s "$CODEX_HOME/auth.json" ] || fail "codex-clean apply must not remove auth.json"

trash_copy="$(find_trash_copy "$(basename "$clean_target")")"
[ -n "$trash_copy" ] || fail "codex-clean apply did not move media-preview file into trash"
assert_file_contains "$trash_copy" "$clean_marker"

if try_capture clean_restore_latest codex-clean restore --latest; then
  :
elif try_capture clean_restore_latest_arg codex-clean restore latest; then
  :
elif try_capture clean_restore_default codex-clean restore; then
  :
else
  fail "codex-clean restore could not restore latest trash entry"
fi

[ -s "$clean_target" ] || fail "codex-clean restore did not restore media-preview file"
[ -s "$clean_ref" ] || fail "codex-clean restore did not restore media-preview ref"
[ -s "$clean_result" ] || fail "codex-clean restore did not restore browser result file"
[ -s "$clean_screenshot" ] || fail "codex-clean restore did not restore browser screenshot"
assert_file_contains "$clean_target" "$clean_marker"

printf 'OK: Codex for TUI ops smoke passed\n'
