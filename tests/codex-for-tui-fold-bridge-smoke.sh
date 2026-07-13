#!/usr/bin/env sh
# Local smoke for codex-tui-fold-bridge (Runtime Emitter MVP).
# Does NOT enable product apply by default; never requires local Gradle.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BRIDGE_PY="$ROOT_DIR/android-arm64-musl/libexec/codex-tui-fold-bridge.py"
WRAPPER_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-tui-fold-bridge"
POLICY_EXAMPLE="$ROOT_DIR/docs/architecture/session-fold-bridge.policy.example"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-fold-bridge-smoke.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  haystack="$1"
  needle="$2"
  label="${3:-content}"
  printf '%s' "$haystack" | grep -F "$needle" >/dev/null 2>&1 || fail "$label missing: $needle"
}

assert_not_contains() {
  haystack="$1"
  needle="$2"
  label="${3:-content}"
  printf '%s' "$haystack" | grep -F "$needle" >/dev/null 2>&1 && fail "$label unexpectedly contains: $needle" || true
}

[ -s "$BRIDGE_PY" ] || fail "missing $BRIDGE_PY"
[ -s "$WRAPPER_ASSET" ] || fail "missing wrapper asset $WRAPPER_ASSET"
[ -s "$POLICY_EXAMPLE" ] || fail "missing policy example $POLICY_EXAMPLE"
sh -n "$WRAPPER_ASSET" || fail "wrapper shell syntax failed"
python3 -m py_compile "$BRIDGE_PY" || fail "fold-bridge py_compile failed"

# Isolate policy + codex home so we never touch device apply path.
export PREFIX="$TMP_ROOT/prefix"
export CODEX_HOME="$TMP_ROOT/codex-home"
export CODEX_TUI_FOLD_BRIDGE=0
export CODEX_TUI_FOLD_BRIDGE_MODE=dry-run
mkdir -p "$PREFIX/local/ops" "$CODEX_HOME/sessions/2026/07/13" "$CODEX_HOME/install-state"

# Default disabled status
status_json="$(PYTHONNOUSERSITE=1 python3 "$BRIDGE_PY" status)" || fail "status failed"
assert_contains "$status_json" '"enabled": false' "status.enabled"
assert_contains "$status_json" '"mode": "dry-run"' "status.mode"

self_json="$(PYTHONNOUSERSITE=1 python3 "$BRIDGE_PY" self-test)" || fail "self-test failed"
assert_contains "$self_json" '"ok": true' "self-test.ok"

# Synthetic rollout with start/done/fail
rollout="$CODEX_HOME/sessions/2026/07/13/rollout-2026-07-13T12-00-00-fold-smoke.jsonl"
python3 - "$rollout" <<'PY'
import json, sys
path = sys.argv[1]
rows = [
    {"timestamp": "2026-07-13T12:00:00Z", "type": "event_msg",
     "payload": {"type": "task_started", "turn_id": "fold-smoke-turn-1"}},
    {"timestamp": "2026-07-13T12:00:01Z", "type": "event_msg",
     "payload": {"type": "task_complete", "turn_id": "fold-smoke-turn-1", "duration_ms": 1000}},
    {"timestamp": "2026-07-13T12:00:02Z", "type": "event_msg",
     "payload": {"type": "task_started", "turn_id": "fold-smoke-turn-2"}},
    {"timestamp": "2026-07-13T12:00:03Z", "type": "event_msg",
     "payload": {"type": "turn_aborted", "turn_id": "fold-smoke-turn-2", "reason": "interrupted"}},
    {"timestamp": "2026-07-13T12:00:04Z", "type": "response_item",
     "payload": {"type": "reasoning", "text": "noise"}},
]
with open(path, "w", encoding="utf-8") as f:
    for row in rows:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
PY

map_out="$(PYTHONNOUSERSITE=1 python3 "$BRIDGE_PY" map-file "$rollout")" || fail "map-file failed"
assert_contains "$map_out" '"actions": 4' "map-file.actions"
assert_contains "$map_out" '"starts": 2' "map-file.starts"
assert_contains "$map_out" '"dones": 1' "map-file.dones"
assert_contains "$map_out" '"fails": 1' "map-file.fails"
assert_contains "$map_out" "codex-session start" "map-file.start-cli"
assert_contains "$map_out" "codex-session done" "map-file.done-cli"
assert_contains "$map_out" "codex-session fail" "map-file.fail-cli"

disc="$(PYTHONNOUSERSITE=1 python3 "$BRIDGE_PY" discover-active --limit 3)" || fail "discover-active failed"
assert_contains "$disc" 'fold-smoke' "discover-active.path"
assert_contains "$disc" '"enabled": false' "discover-active.enabled"

# tail-once dry-run should list actions without needing codex-session
tail_out="$(PYTHONNOUSERSITE=1 python3 "$BRIDGE_PY" tail-once "$rollout")" || fail "tail-once failed"
assert_contains "$tail_out" '"enabled": false' "tail-once.enabled"
assert_contains "$tail_out" 'fold-smoke-turn-1' "tail-once.run"

# watch a single iteration (dry-run; advances offset JSON)
watch_out="$(PYTHONNOUSERSITE=1 python3 "$BRIDGE_PY" watch "$rollout" --interval-ms 200 --max-iters 1)" || fail "watch failed"
printf '%s' "$watch_out" | grep -E 'offset_to|"actions"' >/dev/null 2>&1 || fail "watch output missing offset/actions"

# Policy example must default off
policy_txt="$(cat "$POLICY_EXAMPLE")"
assert_contains "$policy_txt" 'enabled=0' "policy.example.enabled"
assert_contains "$policy_txt" 'mode=dry-run' "policy.example.mode"

# Wrapper resolves py via CODEX_TUI_FOLD_BRIDGE_PY
wrap_out="$(
  CODEX_TUI_FOLD_BRIDGE_PY="$BRIDGE_PY" \
  PREFIX="$PREFIX" CODEX_HOME="$CODEX_HOME" \
  sh "$WRAPPER_ASSET" self-test
)" || fail "wrapper self-test failed"
assert_contains "$wrap_out" '"ok": true' "wrapper.self-test"

printf 'OK: codex-for-tui-fold-bridge-smoke passed\n'
