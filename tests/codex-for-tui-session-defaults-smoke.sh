#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE="$ROOT_DIR/android-arm64-musl/libexec/codex-config-engine.py"
ADAPTER="$ROOT_DIR/android-arm64-musl/libexec/codex-session-defaults.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-session-defaults.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

json_value() {
  file="$1"
  path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

value = json.loads(open(sys.argv[1], encoding="utf-8").read())
for key in sys.argv[2].split("."):
    value = value[key]
print("" if value is None else value)
PY
}

append_settings() {
  transcript="$1"
  effort="$2"
  mode="$3"
  provider="$4"
  python3 - "$transcript" "$effort" "$mode" "$provider" <<'PY'
import datetime as dt
import json
import sys

path, effort, mode, provider = sys.argv[1:]
value = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "type": "event_msg",
    "payload": {
        "type": "thread_settings_applied",
        "thread_settings": {
            "model": "gpt-5.6-sol",
            "model_provider_id": provider,
            "reasoning_effort": effort,
            "collaboration_mode": {"mode": mode, "settings": {}},
        },
    },
}
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(value, ensure_ascii=False) + "\n")
PY
}

run_adapter() {
  command_name="$1"
  shift
  CODEX_FOR_TUI_CONTROL_HOME="$home" \
  CODEX_FOR_TUI_PROFILE_ID="$profile_id" \
  CODEX_FOR_TUI_PROFILE_GENERATION="$generation" \
  CODEX_FOR_TUI_BASELINE_MODEL="$baseline_model" \
  CODEX_FOR_TUI_BASELINE_REASONING_EFFORT="$baseline_effort" \
  CODEX_FOR_TUI_MODEL_PROVIDER_ID="$provider_id" \
  CODEX_HOME="$runtime_home" \
    PYTHONNOUSERSITE=1 python3 "$ADAPTER" "$command_name" "$@"
}

test_binary_build_cache() {
  cache_root="$TMP_ROOT/build-cache"
  cache_home="$cache_root/home"
  fake_binary="$cache_root/codex-zh-bin"
  version_log="$cache_root/version.log"
  mkdir -p "$cache_home"
  cat > "$fake_binary" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' version >> "$CODEX_VERSION_LOG"
  printf '%s\n' "codex-cli 0.144.1-cache"
fi
EOF
  chmod 755 "$fake_binary"
  digest="$(sha256sum "$fake_binary" | awk '{print $1}')"
  (
    export HOME="$cache_home"
    export CODEX_HOME="$cache_home/.codex"
    export CODEX_ZH_STATE_ROOT="$cache_home/.codex/install-state"
    export CODEX_ZH_BIN_SHA256="$digest"
    export CODEX_ZH_RUNTIME_EPOCH="apk-cache-smoke"
    export CODEX_VERSION_LOG="$version_log"
    # shellcheck disable=SC1090
    . "$ROOT_DIR/android-arm64-musl/lib/codex-zh-common.sh"
    first="$(codex_binary_build_key "$fake_binary")"
    second="$(codex_binary_build_key "$fake_binary")"
    [ "$first" = "$second" ] || exit 1
  ) || fail "binary build-key cache did not return a stable key"
  [ "$(wc -l < "$version_log" | tr -d ' ')" = "1" ] ||
    fail "cache hit executed the Codex binary again"
  [ -s "$cache_home/.codex/install-state/binary-build-key-v1" ] ||
    fail "binary build-key cache was not persisted"
}

home="$TMP_ROOT/home/.codex"
mkdir -p "$home/sessions/2026/07/12"
printf '%s\n' '{"data":[{"id":"gpt-5.6-sol"}]}' > "$TMP_ROOT/provider.json"
PYTHONNOUSERSITE=1 python3 "$ENGINE" --codex-home "$home" \
  catalog build \
  --provider-json "$TMP_ROOT/provider.json" \
  --output "$TMP_ROOT/catalog.json" \
  --offline > "$TMP_ROOT/catalog-output.json"
printf '%s\n' '{"OPENAI_API_KEY":"fixture-only"}' > "$TMP_ROOT/auth.json"
PYTHONNOUSERSITE=1 python3 "$ENGINE" --codex-home "$home" \
  profile create \
  --name defaults \
  --mode third_party \
  --provider-name Fixture \
  --base-url https://fixture.example.test/v1 \
  --model gpt-5.6-sol \
  --reasoning-effort medium \
  --auth-file "$TMP_ROOT/auth.json" \
  --catalog-file "$TMP_ROOT/catalog.json" \
  --activate > "$TMP_ROOT/create.json"

profile_id="$(json_value "$TMP_ROOT/create.json" profile.id)"
generation="$(json_value "$TMP_ROOT/create.json" profile.generation)"
baseline_model="$(json_value "$TMP_ROOT/create.json" profile.model)"
baseline_effort="$(json_value "$TMP_ROOT/create.json" profile.reasoning_effort)"
provider_id="$(json_value "$TMP_ROOT/create.json" profile.provider_id)"
runtime_home="$(json_value "$TMP_ROOT/create.json" profile.runtime_home)"
transcript="$home/sessions/2026/07/12/rollout-2026-07-12T00-00-00-019f5475-085a-7f81-8d96-2b8c3a57e397.jsonl"
printf '%s\n' \
  '{"type":"session_meta","payload":{"id":"019f5475-085a-7f81-8d96-2b8c3a57e397","cwd":"/root/workspace"}}' \
  > "$transcript"
append_settings "$transcript" medium default "$provider_id"
append_settings "$transcript" xhigh plan "$provider_id"
append_settings "$transcript" ultra default "$provider_id"

run_adapter migrate-latest > "$TMP_ROOT/migrate.json"
pending="$home/install-state/session-defaults/$profile_id.json"
[ -s "$pending" ] || fail "latest default settings were not staged"
[ "$(json_value "$pending" reasoning_effort)" = "ultra" ] ||
  fail "plan-mode settings replaced the latest default setting"

old_generation="$generation"
PYTHONNOUSERSITE=1 python3 "$ENGINE" --codex-home "$home" \
  profile launch --sqlite-build-key defaults-build-a > "$TMP_ROOT/launch-a.json"
[ ! -e "$pending" ] || fail "profile launch did not consume pending defaults"
[ "$(json_value "$TMP_ROOT/launch-a.json" session_defaults.status)" = "applied" ] ||
  fail "profile launch did not report applied session defaults"
grep -F 'model_reasoning_effort = "ultra"' "$home/config.toml" >/dev/null ||
  fail "ultra reasoning was not materialized"

PYTHONNOUSERSITE=1 python3 "$ENGINE" --codex-home "$home" \
  profile show "$profile_id" > "$TMP_ROOT/show.json"
generation="$(json_value "$TMP_ROOT/show.json" profile.generation)"
baseline_model="$(json_value "$TMP_ROOT/show.json" profile.model)"
baseline_effort="$(json_value "$TMP_ROOT/show.json" profile.reasoning_effort)"
runtime_home="$(json_value "$TMP_ROOT/show.json" profile.runtime_home)"
[ "$generation" != "$old_generation" ] ||
  fail "managed generation did not change after applying defaults"

append_settings "$transcript" high default "$provider_id"
hook_input="$TMP_ROOT/hook.json"
python3 - "$hook_input" "$transcript" <<'PY'
import json
import sys

value = {
    "hook_event_name": "UserPromptSubmit",
    "session_id": "019f5475-085a-7f81-8d96-2b8c3a57e397",
    "transcript_path": sys.argv[2],
}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(value))
PY
run_adapter hook < "$hook_input"
[ "$(json_value "$pending" reasoning_effort)" = "high" ] ||
  fail "hook did not stage changed reasoning"

generation="$old_generation"
baseline_effort="medium"
append_settings "$transcript" low default "$provider_id"
run_adapter hook < "$hook_input"
[ "$(json_value "$pending" reasoning_effort)" = "high" ] ||
  fail "stale-generation hook overwrote a current pending value"

generation="$(json_value "$TMP_ROOT/show.json" profile.generation)"
baseline_effort="ultra"
append_settings "$transcript" ultra default "$provider_id"
run_adapter hook < "$hook_input"
[ ! -e "$pending" ] ||
  fail "same session returning to launch baseline did not cancel pending defaults"

append_settings "$transcript" xhigh plan "$provider_id"
run_adapter migrate-latest > "$TMP_ROOT/plan.json"
[ ! -e "$pending" ] || fail "plan-mode reasoning was staged as a persistent default"

PYTHONPYCACHEPREFIX="$TMP_ROOT/pycache" python3 -m py_compile "$ADAPTER" "$ENGINE"
test_binary_build_cache
printf 'OK: Codex session default persistence smoke passed\n'
