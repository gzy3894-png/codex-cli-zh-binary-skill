#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE="$ROOT_DIR/android-arm64-musl/libexec/codex-config-engine.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-v2-smoke.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "missing '$pattern' in $file"
}

assert_not_contains() {
  file="$1"
  pattern="$2"
  ! grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "unexpected '$pattern' in $file"
}

assert_json() {
  file="$1"
  expression="$2"
  python3 - "$file" "$expression" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
if not eval(sys.argv[2], {"__builtins__": {}, "len": len}, {"v": value}):
    raise SystemExit(f"JSON assertion failed: {sys.argv[2]}")
PY
}

engine() {
  engine_codex_home="$1"
  shift
  PYTHONNOUSERSITE=1 python3 "$ENGINE" --codex-home "$engine_codex_home" "$@"
}

runtime_hash() {
  home="$1"
  {
    for file in \
      "$home/config.toml" \
      "$home/auth.json" \
      "$home/model_catalog.json"
    do
      if [ -f "$file" ]; then
        sha256sum "$file"
      else
        printf 'missing  %s\n' "$file"
      fi
    done
    for directory in \
      "$home/config-profiles" \
      "$home/config-profiles-v2" \
      "$home/config-runtimes"
    do
      [ -d "$directory" ] || continue
      find "$directory" -type f -print |
        LC_ALL=C sort |
        while IFS= read -r file; do
          sha256sum "$file"
        done
    done
  } | sha256sum | awk '{print $1}'
}

assert_dir_empty() {
  directory="$1"
  [ ! -d "$directory" ] ||
    [ -z "$(find "$directory" -mindepth 1 -print -quit)" ] ||
    fail "directory is not empty: $directory"
}

test_profile_crud_and_preservation() {
  home="$TMP_ROOT/crud"
  mkdir -p "$home"
  printf '%s\n' '# user-comment' 'custom_field = "keep-me"' > "$home/config.toml"
  printf '%s\n' '{"OPENAI_API_KEY":"secret-must-not-leak"}' > "$home/auth-input.json"
  printf '%s\n' '{"data":[{"id":"gpt-5.4"}]}' > "$home/provider.json"
  engine "$home" catalog build \
    --provider-json "$home/provider.json" \
    --output "$home/catalog-input.json" \
    --offline > "$home/catalog-build.json"

  engine "$home" profile create \
    --name krill \
    --mode third_party \
    --provider-name OpenAI \
    --base-url https://api.krill-ai.com/codex/v1 \
    --model gpt-5.4 \
    --reasoning-effort high \
    --auth-file "$home/auth-input.json" \
    --catalog-file "$home/catalog-input.json" \
    --activate > "$home/create.json"
  assert_json "$home/create.json" "v['ok'] is True and v['profile']['name'] == 'krill'"
  assert_not_contains "$home/create.json" "secret-must-not-leak"
  assert_contains "$home/config.toml" "# user-comment"
  assert_contains "$home/config.toml" 'custom_field = "keep-me"'
  assert_contains "$home/config.toml" 'model_catalog_json = '
  assert_contains "$home/config.toml" 'model_reasoning_effort = "high"'

  before="$(runtime_hash "$home")"
  set +e
  engine "$home" profile create \
    --name krill \
    --mode official \
    --model gpt-5.5 > "$home/duplicate.json"
  rc=$?
  set -e
  [ "$rc" -eq 3 ] || fail "duplicate profile should exit 3, got $rc"
  [ "$before" = "$(runtime_hash "$home")" ] || fail "duplicate create changed runtime state"

  engine "$home" profile update krill \
    --name krill \
    --model gpt-5.6-sol \
    --reasoning-effort ultra > "$home/update.json"
  assert_json "$home/update.json" "v['profile']['name'] == 'krill' and v['profile']['model'] == 'gpt-5.6-sol'"
  assert_contains "$home/config.toml" 'model = "gpt-5.6-sol"'
  assert_contains "$home/config.toml" 'model_reasoning_effort = "ultra"'

  engine "$home" profile rename krill primary > "$home/rename.json"
  assert_json "$home/rename.json" "v['profile']['name'] == 'primary'"
  engine "$home" profile create \
    --name official \
    --mode official \
    --model gpt-5.5 \
    --reasoning-effort xhigh \
    --activate > "$home/official.json"
  assert_contains "$home/config.toml" "# user-comment"
  assert_contains "$home/config.toml" 'custom_field = "keep-me"'
  assert_contains "$home/config.toml" 'model = "gpt-5.5"'
  assert_contains "$home/config.toml" 'model_reasoning_effort = "xhigh"'
  assert_not_contains "$home/config.toml" 'model_provider = '
  assert_not_contains "$home/config.toml" 'model_catalog_json = '
  engine "$home" status > "$home/status-clean.json"
  assert_json "$home/status-clean.json" "v['runtime_dirty'] is False"
  sed -i 's/model = "gpt-5.5"/model = "gpt-5.4"/' "$home/config.toml"
  engine "$home" status > "$home/status-dirty.json"
  assert_json "$home/status-dirty.json" "v['runtime_dirty'] is True and 'model' in v['runtime_dirty_reasons']"
  engine "$home" profile sync-current official > "$home/sync-current.json"
  assert_json "$home/sync-current.json" "v['profile']['model'] == 'gpt-5.4'"
  engine "$home" status > "$home/status-resynced.json"
  assert_json "$home/status-resynced.json" "v['runtime_dirty'] is False"

  engine "$home" profile delete primary > "$home/delete.json"
  assert_json "$home/delete.json" "v['deleted_name'] == 'primary'"
  set +e
  engine "$home" profile delete official > "$home/delete-active.json"
  rc=$?
  set -e
  [ "$rc" -eq 5 ] || fail "active profile delete should exit 5, got $rc"
  engine "$home" profile list > "$home/list.json"
  assert_json "$home/list.json" "len(v['profiles']) == 1 and v['profiles'][0]['name'] == 'official'"
  [ "$(stat -c '%a' "$home/install-state/config-v2.lock")" = "600" ] ||
    fail "config engine lock is not private"
}

test_transaction_failure_and_crash_recovery() {
  home="$TMP_ROOT/transaction"
  mkdir -p "$home"
  engine "$home" profile create \
    --name stable \
    --mode official \
    --model gpt-5.4 \
    --reasoning-effort high \
    --activate >/dev/null
  before="$(runtime_hash "$home")"

  set +e
  CODEX_CONFIG_FAILPOINT=after-runtime-config-write \
    engine "$home" profile update stable \
      --model gpt-5.6-sol \
      --reasoning-effort ultra > "$home/failure.json"
  rc=$?
  set -e
  [ "$rc" -eq 86 ] || fail "failure injection should exit 86, got $rc"
  [ "$before" = "$(runtime_hash "$home")" ] || fail "handled failure did not roll back"
  [ ! -e "$home/install-state/config-v2-transaction.json" ] ||
    fail "handled failure left a transaction journal"

  set +e
  CODEX_CONFIG_FAILPOINT=crash:after-runtime-config-write \
    engine "$home" profile update stable \
      --model gpt-5.6-terra \
      --reasoning-effort ultra
  rc=$?
  set -e
  [ "$rc" -eq 86 ] || fail "crash injection should exit 86, got $rc"
  [ -e "$home/install-state/config-v2-transaction.json" ] ||
    fail "crash injection did not leave a recoverable journal"
  engine "$home" status > "$home/recovered.json"
  assert_json "$home/recovered.json" "v['recovered_transaction'] is True"
  [ "$before" = "$(runtime_hash "$home")" ] || fail "crash recovery did not restore runtime state"
}

test_profile_integrity_routing_and_secret_cleanup() {
  home="$TMP_ROOT/integrity"
  mkdir -p "$home/sessions" "$home/archived_sessions" "$home/shell_snapshots"
  printf '%s\n' '{"session":"control-home-only"}' > "$home/sessions/control.jsonl"
  printf '%s\n' '{"history":"control-home-only"}' > "$home/history.jsonl"
  printf '%s\n' '{"OPENAI_API_KEY":"secret-backup-check"}' > "$home/auth-input.json"
  printf '%s\n' '{"data":[{"id":"gpt-5.4"}]}' > "$home/provider.json"
  engine "$home" catalog build \
    --provider-json "$home/provider.json" \
    --output "$home/catalog-input.json" \
    --offline >/dev/null

  before="$(runtime_hash "$home")"
  set +e
  engine "$home" profile create \
    --name bad-userinfo \
    --mode third_party \
    --base-url 'https://user:secret-userinfo@example.test/v1' \
    --model gpt-5.4 > "$home/bad-userinfo.json"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "userinfo base URL should exit 2, got $rc"
  assert_not_contains "$home/bad-userinfo.json" "secret-userinfo"
  [ "$before" = "$(runtime_hash "$home")" ] || fail "rejected userinfo URL changed state"

  set +e
  engine "$home" profile create \
    --name bad-query \
    --mode third_party \
    --base-url 'https://example.test/v1?api_key=secret-query' \
    --model gpt-5.4 > "$home/bad-query.json"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "query base URL should exit 2, got $rc"
  assert_not_contains "$home/bad-query.json" "secret-query"

  engine "$home" profile create \
    --name third \
    --mode third_party \
    --provider-name OpenAI \
    --base-url https://api.example.test/v1 \
    --model gpt-5.4 \
    --reasoning-effort high \
    --auth-file "$home/auth-input.json" \
    --catalog-file "$home/catalog-input.json" \
    --activate > "$home/third.json"
  assert_dir_empty "$home/install-state/backups/config-v2"
  engine "$home" catalog status > "$home/catalog-status.json"
  assert_json "$home/catalog-status.json" "v['catalog']['integrity'] == 'ok'"
  engine "$home" profile launch third \
    --sqlite-build-key codex-cli-0.144.1-test-build > "$home/third-launch.json"
  third_runtime="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_home"])' "$home/third-launch.json")"
  third_sqlite="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sqlite_home"])' "$home/third-launch.json")"
  # Shared conversation state: sessions/history symlink to control CODEX_HOME.
  [ -L "$third_runtime/sessions" ] ||
    fail "profile runtime must symlink shared sessions to control home"
  [ -L "$third_runtime/history.jsonl" ] ||
    fail "profile runtime must symlink shared history to control home"
  [ -e "$third_runtime/sessions/control.jsonl" ] ||
    fail "profile runtime must see control-home session rollouts"
  assert_contains "$third_runtime/config.toml" "sqlite_home = \"$third_sqlite\""
  # Write via the shared sessions link so the rollout lives in control home.
  printf '%s\n' '{"session":"preserve-after-profile-delete"}' > "$third_runtime/sessions/keep.jsonl"
  [ -s "$home/sessions/keep.jsonl" ] ||
    fail "shared sessions write did not land in control home"

  sed -i "s#command = \".*print-openai-api-key.sh\"#command = \"/tmp/rogue-auth\"#" "$home/config.toml"
  engine "$home" status > "$home/dirty-auth.json"
  assert_json "$home/dirty-auth.json" "'provider.auth.command' in v['runtime_dirty_reasons']"
  engine "$home" profile activate third >/dev/null

  engine "$home" profile create \
    --name official \
    --mode official \
    --model gpt-5.5 \
    --activate >/dev/null
  printf '%s\n' \
    'model_provider = "rogue"' \
    'model_catalog_json = "/tmp/rogue-models.json"' >> "$home/config.toml"
  engine "$home" status > "$home/dirty-route.json"
  assert_json "$home/dirty-route.json" "'model_provider' in v['runtime_dirty_reasons'] and 'model_catalog_json' in v['runtime_dirty_reasons']"
  engine "$home" profile activate official >/dev/null
  engine "$home" profile delete third >/dev/null
  assert_dir_empty "$home/install-state/backups/config-v2"
  ! grep -R -F "secret-backup-check" \
    "$home/install-state/backups/config-v2" \
    "$home/config-profiles-v2" \
    "$home/config-runtimes" \
    "$home/auth.json" >/dev/null 2>&1 ||
    fail "deleted profile secret remains in live or transaction storage"
  # Profile delete may rmtree the runtime home (sqlite/catalogs), but must never
  # wipe control-home shared conversation history the runtime only linked to.
  [ -s "$home/sessions/keep.jsonl" ] ||
    fail "deleting a profile removed control-home shared sessions"
  [ ! -e "$third_runtime/config.toml" ] ||
    fail "deleted profile runtime config.toml should be gone"


  engine "$home" profile create --name alpha --mode official --model gpt-5.4 > "$home/alpha.json"
  engine "$home" profile create --name beta --mode official --model gpt-5.5 > "$home/beta.json"
  alpha_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"]["id"])' "$home/alpha.json")"
  beta_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"]["id"])' "$home/beta.json")"
  python3 - "$home/config-profiles-v2/profiles/$alpha_id/profile.json" "$beta_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["id"] = sys.argv[2]
path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  set +e
  engine "$home" profile delete alpha > "$home/corrupt-delete.json"
  rc=$?
  set -e
  [ "$rc" -eq 7 ] || fail "corrupt profile identity should exit 7, got $rc"
  [ -d "$home/config-profiles-v2/profiles/$beta_id" ] ||
    fail "corrupt profile identity deleted another profile"
}

test_profile_runtime_config_persistence_and_isolation() {
  home="$TMP_ROOT/runtime-isolation"
  mkdir -p "$home"
  printf '%s\n' '{"data":[{"id":"gpt-5.4"},{"id":"gpt-5.5"}]}' > "$home/provider.json"
  engine "$home" catalog build \
    --provider-json "$home/provider.json" \
    --output "$home/catalog.json" \
    --offline >/dev/null
  printf '%s\n' '{"OPENAI_API_KEY":"alpha-secret"}' > "$home/alpha-auth.json"
  printf '%s\n' '{"OPENAI_API_KEY":"beta-secret"}' > "$home/beta-auth.json"

  engine "$home" profile create \
    --name alpha \
    --mode third_party \
    --provider-name Alpha \
    --base-url https://alpha.example.test/v1 \
    --model gpt-5.4 \
    --reasoning-effort high \
    --auth-file "$home/alpha-auth.json" \
    --catalog-file "$home/catalog.json" \
    --activate > "$home/alpha-create.json"
  engine "$home" profile create \
    --name beta \
    --mode third_party \
    --provider-name Beta \
    --base-url https://beta.example.test/v1 \
    --model gpt-5.5 \
    --reasoning-effort xhigh \
    --auth-file "$home/beta-auth.json" \
    --catalog-file "$home/catalog.json" > "$home/beta-create.json"

  engine "$home" profile launch alpha \
    --sqlite-build-key codex-cli-0.144.1-build-a > "$home/alpha-launch.json"
  alpha_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"]["id"])' "$home/alpha-launch.json")"
  alpha_runtime="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_home"])' "$home/alpha-launch.json")"
  alpha_sqlite="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sqlite_home"])' "$home/alpha-launch.json")"
  printf '%s\n' \
    '' \
    '[profile_local]' \
    '# alpha-runtime-only' \
    'runtime_note = "alpha-only"' >> "$alpha_runtime/config.toml"
  # Shared sessions: write through alpha runtime link; beta must see it too.
  printf '%s\n' '{"session":"alpha-stays-alive"}' > "$alpha_runtime/sessions/alpha.jsonl"
  [ -L "$alpha_runtime/sessions" ] || fail "alpha runtime must symlink shared sessions"

  engine "$home" profile activate beta >/dev/null
  engine "$home" profile launch beta \
    --sqlite-build-key codex-cli-0.144.1-build-a > "$home/beta-launch.json"
  beta_runtime="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_home"])' "$home/beta-launch.json")"
  beta_sqlite="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sqlite_home"])' "$home/beta-launch.json")"
  [ "$alpha_runtime" != "$beta_runtime" ] ||
    fail "different profiles reused the same runtime home"
  [ "$alpha_sqlite" != "$beta_sqlite" ] ||
    fail "different profiles reused the same SQLite home"
  assert_contains "$alpha_runtime/config.toml" 'base_url = "https://alpha.example.test/v1"'
  assert_contains "$beta_runtime/config.toml" 'base_url = "https://beta.example.test/v1"'
  assert_not_contains "$beta_runtime/config.toml" "https://alpha.example.test/v1"
  assert_not_contains "$beta_runtime/config.toml" "alpha-runtime-only"
  [ -L "$beta_runtime/sessions" ] || fail "beta runtime must symlink shared sessions"
  [ -e "$beta_runtime/sessions/alpha.jsonl" ] ||
    fail "beta must see shared alpha session state"
  assert_contains "$beta_runtime/sessions/alpha.jsonl" '"session":"alpha-stays-alive"'

  engine "$home" profile sync-runtime alpha \
    --source-dir "$alpha_runtime" > "$home/alpha-sync.json"
  alpha_base="$home/config-profiles-v2/profiles/$alpha_id/legacy-config.toml"
  alpha_profile_dir="$home/config-profiles-v2/profiles/$alpha_id"
  alpha_runtime_local="$alpha_profile_dir/runtime-local.toml"
  [ -s "$alpha_runtime_local" ] ||
    fail "runtime-local overlay was not persisted after sync"
  assert_contains "$alpha_runtime_local" "# alpha-runtime-only"
  assert_contains "$alpha_runtime_local" 'runtime_note = "alpha-only"'
  assert_not_contains "$alpha_base" "sqlite_home"

  engine "$home" profile launch alpha \
    --sqlite-build-key codex-cli-0.144.1-build-b > "$home/alpha-relaunch.json"
  alpha_sqlite_b="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sqlite_home"])' "$home/alpha-relaunch.json")"
  [ "$alpha_sqlite" != "$alpha_sqlite_b" ] ||
    fail "different Codex builds reused the same SQLite home"
  assert_contains "$alpha_runtime/config.toml" "# alpha-runtime-only"
  assert_contains "$alpha_runtime/config.toml" 'runtime_note = "alpha-only"'
  assert_contains "$alpha_runtime/sessions/alpha.jsonl" '"session":"alpha-stays-alive"'
  assert_not_contains "$beta_runtime/config.toml" "alpha-runtime-only"

  # 2.5.6: materialize uses control common ⊕ managed, not legacy-config snapshots.
  # Write root-level common key (prepend) so TOML round-trip keeps it.
  python3 - "$home/config.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if 'common_marker = "keep-me"' not in text:
    path.write_text('common_marker = "keep-me"\n' + text, encoding="utf-8")
PY
  printf '%s\n' '# POISON_LEGACY' 'poison_legacy = true' >> "$alpha_base"
  engine "$home" profile launch alpha \
    --sqlite-build-key codex-cli-0.144.1-build-c > "$home/alpha-common-launch.json"
  assert_contains "$home/config.toml" 'common_marker = "keep-me"'
  assert_not_contains "$home/config.toml" 'poison_legacy'
  assert_not_contains "$home/config.toml" 'POISON_LEGACY'
  assert_contains "$alpha_runtime/config.toml" 'common_marker = "keep-me"'
  assert_not_contains "$alpha_runtime/config.toml" 'poison_legacy'

  # Removing a control-owned common key must not resurrect it from the old runtime.
  python3 - "$home/config.toml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = [
    line for line in path.read_text(encoding="utf-8").splitlines()
    if line != 'common_marker = "keep-me"'
]
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
  engine "$home" profile launch alpha \
    --sqlite-build-key codex-cli-0.144.1-build-d > "$home/alpha-common-delete.json"
  assert_not_contains "$home/config.toml" 'common_marker = "keep-me"'
  assert_not_contains "$alpha_runtime/config.toml" 'common_marker = "keep-me"'

  # Explicitly synced runtime-only keys remain in the separate overlay.
  # The previous launch already materialized [profile_local]; append within
  # that table instead of declaring the same TOML table twice.
  printf '%s\n' 'runtime_sync_marker = "alpha-sync"' \
    >> "$alpha_runtime/config.toml"
  engine "$home" profile sync-runtime alpha \
    --source-dir "$alpha_runtime" > "$home/alpha-sync-runtime-local.json"
  alpha_profile_dir="$home/config-profiles-v2/profiles/$alpha_id"
  [ -s "$alpha_profile_dir/runtime-local.toml" ] ||
    fail "runtime-local overlay was not persisted"
  assert_contains "$alpha_profile_dir/runtime-local.toml" 'runtime_note = "alpha-only"'
  assert_contains "$alpha_profile_dir/runtime-local.toml" 'runtime_sync_marker = "alpha-sync"'
  assert_not_contains "$alpha_profile_dir/runtime-local.toml" 'common_marker = "keep-me"'
  engine "$home" profile launch alpha \
    --sqlite-build-key codex-cli-0.144.1-build-e > "$home/alpha-runtime-local-launch.json"
  assert_contains "$alpha_runtime/config.toml" 'runtime_note = "alpha-only"'

  # Global compact policy is index-owned; profile meta copies are not the source of truth.
  engine "$home" compact-policy fixed 250000 > "$home/compact-fixed.json"
  assert_contains "$home/config.toml" 'model_auto_compact_token_limit = 250000'
  engine "$home" profile activate beta >/dev/null
  engine "$home" profile launch beta \
    --sqlite-build-key codex-cli-0.144.1-build-c > "$home/beta-common-launch.json"
  assert_contains "$home/config.toml" 'model_auto_compact_token_limit = 250000'
  assert_not_contains "$home/config.toml" 'common_marker = "keep-me"'
  assert_contains "$beta_runtime/config.toml" 'model_auto_compact_token_limit = 250000'
}

test_compact_policy_without_active_profile_persists_metadata() {
  home="$TMP_ROOT/no-active"
  mkdir -p "$home"
  printf '%s\n' 'common_marker = "keep-me"' > "$home/config.toml"

  engine "$home" compact-policy fixed 123456 > "$home/fixed.json"
  python3 - "$home/config-profiles-v2/index.json" <<'PY'
import json
import sys

value = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert value["compact_policy"] == {"mode": "fixed", "value": 123456}
assert "model_auto_compact_token_limit" in value["runtime_managed"]["root_keys"]
PY
  assert_contains "$home/config.toml" 'model_auto_compact_token_limit = 123456'

  engine "$home" compact-policy follow-model > "$home/follow.json"
  python3 - "$home/config-profiles-v2/index.json" <<'PY'
import json
import sys

value = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert value["compact_policy"] == {"mode": "follow-model"}
assert "model_auto_compact_token_limit" not in value["runtime_managed"]["root_keys"]
PY
  assert_not_contains "$home/config.toml" 'model_auto_compact_token_limit = '
}

write_v1_official_fixture() {
  home="$1"
  mkdir -p "$home/config-profiles/legacy/install-state"
  printf '%s\n' 'legacy' > "$home/config-profiles/current"
  printf '%s\n' \
    '# legacy-comment' \
    'custom_field = "legacy-keep"' \
    'model = "gpt-5.4"' \
    'model_reasoning_effort = "high"' \
    'model_auto_compact_token_limit = 220000' > "$home/config.toml"
  cp "$home/config.toml" "$home/config-profiles/legacy/config.toml"
  printf '%s\n' 'official-login' > "$home/config-profiles/legacy/install-state/official-login-mode"
}

write_v1_multi_fixture() {
  home="$1"
  mkdir -p \
    "$home/config-profiles/alpha/install-state" \
    "$home/config-profiles/beta/install-state" \
    "$home/install-state"
  printf '%s\n' 'alpha' > "$home/config-profiles/current"
  printf '%s\n' \
    '# alpha-config' \
    'model = "gpt-5.4"' \
    'model_reasoning_effort = "high"' > "$home/config-profiles/alpha/config.toml"
  printf '%s\n' \
    '# beta-config' \
    'model = "gpt-5.5"' \
    'model_reasoning_effort = "xhigh"' > "$home/config-profiles/beta/config.toml"
  printf '%s\n' 'official-login' > "$home/config-profiles/alpha/install-state/official-login-mode"
  printf '%s\n' 'official-login' > "$home/config-profiles/beta/install-state/official-login-mode"
  cp "$home/config-profiles/alpha/config.toml" "$home/config.toml"
  printf '%s\n' 'official-login' > "$home/install-state/official-login-mode"
}

test_v1_migration_policies_and_rollback() {
  follow="$TMP_ROOT/migrate-follow"
  write_v1_official_fixture "$follow"
  before="$(runtime_hash "$follow")"
  engine "$follow" migrate-v1 --compact-policy follow-model > "$follow/migrate.json"
  assert_json "$follow/migrate.json" "v['migrated'] is True and v['compact_policy']['mode'] == 'follow-model'"
  assert_contains "$follow/config.toml" "# legacy-comment"
  assert_contains "$follow/config.toml" 'custom_field = "legacy-keep"'
  assert_not_contains "$follow/config.toml" "model_auto_compact_token_limit"
  engine "$follow" profile show legacy > "$follow/show.json"
  assert_json "$follow/show.json" "v['profile']['model'] == 'gpt-5.4' and v['profile']['reasoning_effort'] == 'high'"
  engine "$follow" migrate-v1 --compact-policy fixed > "$follow/idempotent.json"
  assert_json "$follow/idempotent.json" "v['migrated'] is False and v['reason'] == 'already-v2'"
  engine "$follow" rollback-v1 > "$follow/rollback.json"
  [ "$before" = "$(runtime_hash "$follow")" ] || fail "V1 rollback did not restore runtime state"

  fixed="$TMP_ROOT/migrate-fixed"
  write_v1_official_fixture "$fixed"
  engine "$fixed" migrate-v1 --compact-policy fixed > "$fixed/migrate.json"
  assert_contains "$fixed/config.toml" "model_auto_compact_token_limit = 220000"
  engine "$fixed" compact-policy follow-model > "$fixed/follow.json"
  assert_not_contains "$fixed/config.toml" "model_auto_compact_token_limit"
  engine "$fixed" compact-policy fixed 180000 > "$fixed/fixed.json"
  assert_contains "$fixed/config.toml" "model_auto_compact_token_limit = 180000"
}

test_v1_migration_crash_recovery() {
  home="$TMP_ROOT/migrate-crash"
  write_v1_official_fixture "$home"
  before="$(runtime_hash "$home")"
  set +e
  CODEX_CONFIG_FAILPOINT=crash:after-v1-profile-reset \
    engine "$home" migrate-v1 --compact-policy follow-model
  rc=$?
  set -e
  [ "$rc" -eq 86 ] || fail "migration crash injection should exit 86, got $rc"
  engine "$home" status > "$home/recovered.json"
  assert_json "$home/recovered.json" "v['schema_version'] == 1 and v['recovered_transaction'] is True"
  [ "$before" = "$(runtime_hash "$home")" ] || fail "migration crash recovery changed V1 runtime state"
}

test_v1_migration_retry_and_transactional_rollback() {
  retry="$TMP_ROOT/migrate-retry"
  write_v1_multi_fixture "$retry"
  retry_v1="$(runtime_hash "$retry")"
  set +e
  CODEX_CONFIG_FAILPOINT=crash:after-v1-profile-reset \
    engine "$retry" migrate-v1 --compact-policy follow-model
  rc=$?
  set -e
  [ "$rc" -eq 86 ] || fail "migration retry crash should exit 86, got $rc"
  engine "$retry" migrate-v1 --compact-policy follow-model > "$retry/retry.json"
  assert_json "$retry/retry.json" "v['migrated'] is True and len(v['imported_profiles']) == 2"
  engine "$retry" profile list > "$retry/list.json"
  assert_json "$retry/list.json" "len(v['profiles']) == 2 and {item['name'] for item in v['profiles']} == {'alpha', 'beta'}"
  engine "$retry" rollback-v1 >/dev/null
  [ "$retry_v1" = "$(runtime_hash "$retry")" ] ||
    fail "direct migration retry did not preserve the full V1 recovery point"

  rollback="$TMP_ROOT/rollback-crash"
  write_v1_multi_fixture "$rollback"
  rollback_v1="$(runtime_hash "$rollback")"
  engine "$rollback" migrate-v1 --compact-policy follow-model >/dev/null
  rollback_v2="$(runtime_hash "$rollback")"
  set +e
  CODEX_CONFIG_FAILPOINT=crash:after-v1-rollback-restore \
    engine "$rollback" rollback-v1
  rc=$?
  set -e
  [ "$rc" -eq 86 ] || fail "rollback crash should exit 86, got $rc"
  [ -f "$rollback/install-state/config-v2-transaction.json" ] ||
    fail "rollback crash did not leave a recovery journal"
  engine "$rollback" status > "$rollback/recovered.json"
  assert_json "$rollback/recovered.json" "v['schema_version'] == 2 and v['recovered_transaction'] is True"
  [ "$rollback_v2" = "$(runtime_hash "$rollback")" ] ||
    fail "rollback crash recovery did not restore the complete V2 state"
  engine "$rollback" rollback-v1 >/dev/null
  [ "$rollback_v1" = "$(runtime_hash "$rollback")" ] ||
    fail "transactional rollback did not restore the complete V1 state"
}

test_v1_migration_ignores_runtime_pollution() {
  home="$TMP_ROOT/migrate-polluted"
  write_v1_official_fixture "$home"
  legacy="$home/config-profiles/legacy"
  mkdir -p "$legacy/.tmp/plugins/.git/objects/pack" "$legacy/sessions/2026/07/10"
  printf '%s\n' 'old-state-db' > "$legacy/state_5.sqlite"
  printf '%s\n' '{"session":"keep"}' > "$legacy/sessions/2026/07/10/rollout.jsonl"
  mkfifo "$legacy/.tmp/plugins/.git/objects/pack/transient.pipe"

  engine "$home" migrate-v1 --compact-policy follow-model > "$home/migrate.json"
  assert_json "$home/migrate.json" "v['migrated'] is True and len(v['imported_profiles']) == 1"
  [ -p "$legacy/.tmp/plugins/.git/objects/pack/transient.pipe" ] ||
    fail "V1 migration modified transient runtime files"
  [ -s "$legacy/state_5.sqlite" ] ||
    fail "V1 migration removed the legacy SQLite state"

  engine "$home" profile launch legacy \
    --sqlite-build-key codex-cli-0.144.1-test-build > "$home/launch.json"
  assert_json "$home/launch.json" "v['runtime_home'].endswith('/config-profiles/legacy')"
  assert_contains "$legacy/config.toml" 'model = "gpt-5.4"'
  assert_contains "$legacy/sessions/2026/07/10/rollout.jsonl" '"session":"keep"'
}

test_existing_profile_catalog_is_normalized_without_refresh() {
  home="$TMP_ROOT/catalog-upgrade"
  mkdir -p "$home"
  printf '%s\n' \
    '{"data":[{"id":"gpt-5.4"},{"id":"codex-auto-review"},{"id":"codex-auto-fast"}]}' \
    > "$home/provider.json"
  engine "$home" catalog build \
    --provider-json "$home/provider.json" \
    --output "$home/legacy-catalog.json" \
    --offline >/dev/null
  python3 - "$home/legacy-catalog.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
for model in value["models"]:
    if model["slug"].startswith("codex-auto-"):
        model["visibility"] = "list"
text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
path.write_text(text, encoding="utf-8")
meta_path = path.with_suffix(path.suffix + ".meta.json")
meta = json.loads(meta_path.read_text(encoding="utf-8"))
meta["sha256"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
meta_path.write_text(
    json.dumps(meta, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
  engine "$home" profile create \
    --name upgraded \
    --mode third_party \
    --base-url https://upgrade.example.test/v1 \
    --model gpt-5.4 \
    --catalog-file "$home/legacy-catalog.json" \
    --activate > "$home/create.json"
  profile_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"]["id"])' "$home/create.json")"
  profile_catalog="$home/config-profiles-v2/profiles/$profile_id/model_catalog.json"
  assert_contains "$profile_catalog" '"visibility": "list"'

  engine "$home" profile launch upgraded \
    --sqlite-build-key codex-cli-0.144.1-existing-catalog > "$home/launch.json"
  runtime_home="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_home"])' "$home/launch.json")"
  python3 - "$runtime_home/model_catalog.json" <<'PY'
import json
import sys
from pathlib import Path

models = {
    item["slug"]: item
    for item in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["models"]
}
assert models["gpt-5.4"]["visibility"] != "hide"
assert models["codex-auto-review"]["visibility"] == "hide"
assert models["codex-auto-fast"]["visibility"] == "hide"
PY

  engine "$home" profile sync-runtime upgraded \
    --source-dir "$runtime_home" >/dev/null
  python3 - "$profile_catalog" <<'PY'
import json
import sys
from pathlib import Path

models = {
    item["slug"]: item
    for item in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["models"]
}
assert models["gpt-5.4"]["visibility"] != "hide"
assert models["codex-auto-review"]["visibility"] == "list"
assert models["codex-auto-fast"]["visibility"] == "list"
PY
  engine "$home" profile launch upgraded \
    --sqlite-build-key codex-cli-0.144.1-existing-catalog-b > "$home/relaunch.json"
  runtime_home="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_home"])' "$home/relaunch.json")"
  python3 - "$runtime_home/model_catalog.json" <<'PY'
import json
import sys
from pathlib import Path

models = {
    item["slug"]: item
    for item in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["models"]
}
assert models["gpt-5.4"]["visibility"] != "hide"
assert models["codex-auto-review"]["visibility"] == "hide"
assert models["codex-auto-fast"]["visibility"] == "hide"
PY
}

test_model_catalog_merge_and_cache_fallback() {
  home="$TMP_ROOT/catalog"
  mkdir -p "$home"
  printf '%s\n' \
    '{"data":[{"id":"gpt-5.4"},{"id":"gpt-5.5"},{"id":"gpt-5.6-sol"},{"id":"gpt-5.6-terra"},{"id":"gpt-5.6-luna"},{"id":"codex-auto-review"},{"id":"codex-auto-sol"},{"id":"codex-auto-fast"},{"id":"vendor-sol"},{"id":"vendor-unknown"}]}' \
    > "$home/provider.json"
  printf '%s\n' \
    '{"codex-auto-sol":"gpt-5.6-sol","vendor-sol":"gpt-5.6-sol"}' \
    > "$home/mapping.json"

  engine "$home" catalog build \
    --provider-json "$home/provider.json" \
    --output "$home/catalog.json" \
    --mapping-file "$home/mapping.json" \
    --offline > "$home/build.json"
  assert_json "$home/build.json" "v['known_model_count'] == 8 and v['unknown_models'] == ['codex-auto-fast', 'vendor-unknown']"
  printf '%s\n' '{"data":[{"id":"gpt-5.4"}]}' > "$home/provider-changed.json"
  set +e
  CODEX_CONFIG_FAILPOINT=after-catalog-meta-write \
    engine "$home" catalog build \
      --provider-json "$home/provider-changed.json" \
      --output "$home/catalog.json" \
      --offline > "$home/catalog-pair-failure.json"
  rc=$?
  set -e
  [ "$rc" -eq 86 ] || fail "catalog pair failure injection should exit 86, got $rc"
  python3 - "$home/catalog.json" "$home/catalog.json.meta.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

catalog = Path(sys.argv[1])
meta = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
actual = hashlib.sha256(catalog.read_bytes()).hexdigest()
if actual == meta.get("sha256"):
    raise SystemExit("catalog failure injection did not create a detectable mismatch")
PY
  engine "$home" catalog build \
    --provider-json "$home/provider.json" \
    --output "$home/catalog.json" \
    --mapping-file "$home/mapping.json" \
    --offline > "$home/build-repaired.json"
  python3 - "$home/catalog.json" "$home/catalog.json.meta.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

catalog = Path(sys.argv[1])
meta = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
actual = hashlib.sha256(catalog.read_bytes()).hexdigest()
if actual != meta.get("sha256"):
    raise SystemExit("catalog rebuild did not repair the data/metadata pair")
PY
  python3 - "$home/catalog.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    models = {item["slug"]: item for item in json.load(handle)["models"]}

assert models["gpt-5.4"]["context_window"] == 272000
assert models["gpt-5.4"]["max_context_window"] == 1000000
assert models["gpt-5.5"]["context_window"] == 272000
assert models["gpt-5.6-sol"]["context_window"] == 372000
assert models["gpt-5.6-terra"]["context_window"] == 372000
assert models["gpt-5.6-luna"]["context_window"] == 372000
assert [item["effort"] for item in models["gpt-5.6-sol"]["supported_reasoning_levels"]][-2:] == ["max", "ultra"]
assert [item["effort"] for item in models["gpt-5.6-terra"]["supported_reasoning_levels"]][-2:] == ["max", "ultra"]
assert [item["effort"] for item in models["gpt-5.6-luna"]["supported_reasoning_levels"]][-1:] == ["max"]
assert models["gpt-5.4"]["visibility"] != "hide"
assert models["codex-auto-review"]["visibility"] == "hide"
assert models["codex-auto-sol"]["visibility"] == "hide"
assert models["codex-auto-fast"]["visibility"] == "hide"
assert [item["effort"] for item in models["codex-auto-sol"]["supported_reasoning_levels"]][-2:] == ["max", "ultra"]
assert models["codex-auto-fast"]["supported_reasoning_levels"] == []
assert models["vendor-sol"]["context_window"] == 372000
assert models["vendor-unknown"]["context_window"] is None
assert models["vendor-unknown"]["default_reasoning_level"] is None
assert models["vendor-unknown"]["supported_reasoning_levels"] == []
assert models["vendor-unknown"]["base_instructions"]
assert "Codex" in models["vendor-unknown"]["base_instructions"]
PY
  assert_json "$home/catalog.json.meta.json" "v['unknown_model_instruction_source'] == 'gpt-5.4'"
  assert_json "$home/catalog.json.meta.json" "v['upstream']['source'] == 'bundled-mirror'"
  engine "$home" catalog inspect \
    --catalog-file "$home/catalog.json" \
    --model gpt-5.6-sol > "$home/inspect-sol.json"
  assert_json "$home/inspect-sol.json" "v['model']['resolved_context_window'] == 372000 and v['model']['effective_context_window'] == 353400 and v['model']['auto_compact_token_limit'] == 334800 and v['model']['reasoning_levels'][-1] == 'ultra'"
  engine "$home" catalog inspect \
    --catalog-file "$home/catalog.json" \
    --model vendor-unknown > "$home/inspect-unknown.json"
  assert_json "$home/inspect-unknown.json" "v['model']['conservative_fallback'] is True and v['model']['auto_compact_token_limit'] is None"

  cached="$TMP_ROOT/catalog-cache"
  mkdir -p "$cached"
  mirror_url="file://$ROOT_DIR/android-arm64-musl/data/openai-models.json"
  CODEX_CONFIG_OFFICIAL_CATALOG_URL="$mirror_url" \
    engine "$cached" catalog build \
      --provider-json "$home/provider.json" \
      --output "$cached/first.json" \
      --mapping-file "$home/mapping.json" > "$cached/first-output.json"
  CODEX_CONFIG_CATALOG_OFFLINE=1 \
    engine "$cached" catalog build \
      --provider-json "$home/provider.json" \
      --output "$cached/second.json" \
      --mapping-file "$home/mapping.json" > "$cached/second-output.json"
  assert_json "$cached/second.json.meta.json" "v['upstream']['source'] == 'last-known-good'"
}

[ -x "$ENGINE" ] || fail "configuration engine is not executable"
PYTHONPYCACHEPREFIX="$TMP_ROOT/pycache" python3 -m py_compile "$ENGINE"

printf 'RUN profile CRUD and preservation\n'
test_profile_crud_and_preservation
printf 'RUN transaction failure and crash recovery\n'
test_transaction_failure_and_crash_recovery
printf 'RUN profile integrity, routing and secret cleanup\n'
test_profile_integrity_routing_and_secret_cleanup
printf 'RUN profile runtime config persistence and isolation\n'
test_profile_runtime_config_persistence_and_isolation
printf 'RUN compact policy without active profile metadata persistence\n'
test_compact_policy_without_active_profile_persists_metadata
printf 'RUN V1 migration policies and rollback\n'
test_v1_migration_policies_and_rollback
printf 'RUN V1 migration crash recovery\n'
test_v1_migration_crash_recovery
printf 'RUN V1 migration retry and transactional rollback\n'
test_v1_migration_retry_and_transactional_rollback
printf 'RUN V1 migration ignores runtime pollution\n'
test_v1_migration_ignores_runtime_pollution
printf 'RUN existing profile catalog normalization without refresh\n'
test_existing_profile_catalog_is_normalized_without_refresh
printf 'RUN model catalog merge and cache fallback\n'
test_model_catalog_merge_and_cache_fallback
printf 'OK: Codex for TUI config V2 smoke tests passed\n'
