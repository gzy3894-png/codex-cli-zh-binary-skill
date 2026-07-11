#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
UPGRADER="$SCRIPT_DIR/codex-apk-upgrade.sh"
ENGINE="$SCRIPT_DIR/libexec/codex-config-engine.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-apk-upgrade-smoke.XXXXXX")"

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
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 ||
    fail "missing '$pattern' in $file"
}

assert_not_contains() {
  file="$1"
  pattern="$2"
  ! grep -F -- "$pattern" "$file" >/dev/null 2>&1 ||
    fail "unexpected '$pattern' in $file"
}

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

prepare_test_payload() {
  payload="$TMP_ROOT/payload"
  support="$TMP_ROOT/support"
  binary_root="$TMP_ROOT/binary"
  rm -rf "$payload" "$support" "$binary_root"
  mkdir -p "$payload" "$support" "$binary_root"

  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    mkdir -p "$support/$(dirname "$relative")"
    cp "$SCRIPT_DIR/$relative" "$support/$relative"
    chmod "$(codex_support_file_mode "$relative")" "$support/$relative"
  done <<EOF
$(codex_support_file_list)
EOF

  fake_binary="$binary_root/codex-0.144.1-zh-aarch64-unknown-linux-musl"
  cat > "$fake_binary" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "codex-cli 0.144.1-test"
  exit 0
fi
printf 'fake-codex:%s:%s\n' "${CODEX_HOME:-}" "${CODEX_SQLITE_HOME:-}" >> "${CODEX_TEST_LOG:-/dev/null}"
EOF
  chmod 755 "$fake_binary"

  support_archive="codex-support-2.4.3.tgz"
  binary_archive="codex-test-0.144.1.tgz"
  tar -czf "$payload/$support_archive" -C "$support" .
  tar -czf "$payload/$binary_archive" -C "$binary_root" .
  support_sha="$(sha256_file "$payload/$support_archive")"
  archive_sha="$(sha256_file "$payload/$binary_archive")"
  binary_sha="$(sha256_file "$fake_binary")"
  cat > "$payload/manifest.properties" <<EOF
schema_version=1
release=2.4.3
version_code=58
codex_version=0.144.1
target=aarch64-unknown-linux-musl
runtime_epoch=apk-2.4.3
support_archive=$support_archive
support_sha256=$support_sha
support_file_count=31
binary_archive=$binary_archive
binary_archive_sha256=$archive_sha
binary_sha256=$binary_sha
EOF
  printf '%s  manifest.properties\n' "$(sha256_file "$payload/manifest.properties")" \
    > "$payload/manifest.sha256"
}

write_old_catalog() {
  output="$1"
  python3 - "$output" <<'PY'
import json
import sys
from pathlib import Path

models = []
for slug in ("gpt-5.4", "gpt-5.5", "gpt-5.6-sol", "codex-auto-review"):
    models.append(
        {
            "slug": slug,
            "display_name": slug,
            "description": slug,
            "visibility": "list",
            "context_window": 272000,
            "max_context_window": 272000,
            "auto_compact_token_limit": 220000,
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                {"effort": effort}
                for effort in ("low", "medium", "high", "xhigh")
            ],
            "base_instructions": "You are Codex",
            "input_modalities": ["text"],
        }
    )
Path(sys.argv[1]).write_text(
    json.dumps({"models": models}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

write_third_party_config() {
  output="$1"
  provider_name="$2"
  base_url="$3"
  effort="$4"
  catalog_path="$5"
  cat > "$output" <<EOF
# user-config-$provider_name
custom_user_value = "preserve-$provider_name"
model_provider = "custom"
model = "gpt-5.6-sol"
model_reasoning_effort = "$effort"
model_auto_compact_token_limit = 220000
model_catalog_json = "$catalog_path"

[model_providers.custom]
name = "$provider_name"
base_url = "$base_url"
wire_api = "responses"
requires_openai_auth = false
EOF
}

run_upgrade() {
  home="$1"
  install="$2"
  scripts="$3"
  shift 3
  HOME="$(dirname "$home")" \
  CODEX_HOME="$home" \
  CODEX_APK_UPGRADE_CODEX_HOME="$home" \
  CODEX_APK_UPGRADE_INSTALL_DIR="$install" \
  CODEX_APK_UPGRADE_SCRIPT_ROOT="$scripts" \
  CODEX_APK_UPGRADE_ASSET_DIR="$TMP_ROOT/payload" \
  CODEX_APK_UPGRADE_ALLOW_TEST_PAYLOAD=1 \
  CODEX_APK_UPGRADE_SKIP_REFRESH=1 \
    "$@" sh "$UPGRADER"
}

test_real_241_fault_upgrade() {
  root="$TMP_ROOT/fault"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p \
    "$home/config-profiles/krill/sessions/2026/07/10" \
    "$home/sessions/2026/07/10" \
    "$install"
  write_old_catalog "$home/model_catalog.json"
  cp "$home/model_catalog.json" "$home/config-profiles/krill/model_catalog.json"
  write_third_party_config \
    "$home/config.toml" "Root Site" "https://root.example.test/v1" "xhigh" \
    "$home/model_catalog.json"
  write_third_party_config \
    "$home/config-profiles/krill/config.toml" "Krill" \
    "https://krill.example.test/v1" "medium" \
    "$home/config-profiles/krill/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"root-secret"}' > "$home/auth.json"
  printf '%s\n' '{"OPENAI_API_KEY":"krill-secret"}' > "$home/config-profiles/krill/auth.json"
  printf '%s\n' krill > "$home/config-profiles/current"
  printf '%s\n' '{"session":"root-preserve"}' > "$home/sessions/2026/07/10/root.jsonl"
  printf '%s\n' '{"history":"root-preserve"}' > "$home/history.jsonl"
  printf '%s\n' old-root-sqlite > "$home/state_5.sqlite"
  printf '%s\n' '{"session":"krill-preserve"}' \
    > "$home/config-profiles/krill/sessions/2026/07/10/krill.jsonl"
  printf '%s\n' old-krill-sqlite > "$home/config-profiles/krill/state_5.sqlite"

  run_upgrade "$home" "$install" "$scripts"

  python3 - "$home" "$install" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
install = Path(sys.argv[2])
index = json.loads((home / "config-profiles-v2/index.json").read_text(encoding="utf-8"))
profiles = []
for directory in (home / "config-profiles-v2/profiles").iterdir():
    if directory.is_dir():
        meta = json.loads((directory / "profile.json").read_text(encoding="utf-8"))
        managed = (directory / "managed.toml").read_text(encoding="utf-8")
        profiles.append((meta, managed, directory))
assert len(profiles) == 2
active = next(item for item in profiles if item[0]["id"] == index["active_profile_id"])
krill = next(item for item in profiles if item[0]["name"] == "krill")
assert "https://root.example.test/v1" in active[1]
assert 'model_reasoning_effort = "xhigh"' in active[1]
assert "https://krill.example.test/v1" in krill[1]
assert 'model_reasoning_effort = "medium"' in krill[1]
root_config = (home / "config.toml").read_text(encoding="utf-8")
assert "https://root.example.test/v1" in root_config
assert 'custom_user_value = "preserve-Root Site"' in root_config
assert "model_auto_compact_token_limit" not in root_config
runtime = Path(active[0]["runtime_home"])
assert (runtime / "sessions/2026/07/10/root.jsonl").is_file()
assert (runtime / "history.jsonl").is_file()
assert not (runtime / "state_5.sqlite").exists()
assert (home / "state_5.sqlite").is_file()
assert (home / "config-profiles/krill/state_5.sqlite").is_file()
krill_runtime = Path(krill[0]["runtime_home"])
assert krill_runtime != home / "config-profiles/krill"
assert (krill_runtime / "sessions/2026/07/10/krill.jsonl").is_file()
catalog = json.loads((runtime / "model_catalog.json").read_text(encoding="utf-8"))
models = {item["slug"]: item for item in catalog["models"]}
sol = models["gpt-5.6-sol"]
assert sol["context_window"] == 372000
assert sol["default_reasoning_level"] == "low"
assert [item["effort"] for item in sol["supported_reasoning_levels"]][-2:] == ["max", "ultra"]
assert models["codex-auto-review"]["visibility"] == "hide"
launch = json.loads(
    (home / "install-state/apk-upgrades/2.4.3/launch-check.json").read_text(encoding="utf-8")
)
assert launch["runtime_home"] == str(runtime)
assert "apk-2.4.3" in launch["sqlite_home"]
assert (install / "codex").is_file()
PY
}

test_2311_v1_only_upgrade() {
  root="$TMP_ROOT/v2311"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p \
    "$home/config-profiles/alpha" \
    "$home/config-profiles/beta" \
    "$install"
  write_old_catalog "$home/config-profiles/alpha/model_catalog.json"
  cp "$home/config-profiles/alpha/model_catalog.json" \
    "$home/config-profiles/beta/model_catalog.json"
  write_third_party_config \
    "$home/config-profiles/alpha/config.toml" "Alpha 2.3.11" \
    "https://alpha-2311.example.test/v1" "high" \
    "$home/config-profiles/alpha/model_catalog.json"
  write_third_party_config \
    "$home/config-profiles/beta/config.toml" "Beta 2.3.11" \
    "https://beta-2311.example.test/v1" "xhigh" \
    "$home/config-profiles/beta/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"alpha-secret"}' \
    > "$home/config-profiles/alpha/auth.json"
  printf '%s\n' '{"OPENAI_API_KEY":"beta-secret"}' \
    > "$home/config-profiles/beta/auth.json"
  printf '%s\n' beta > "$home/config-profiles/current"

  run_upgrade "$home" "$install" "$scripts"

  python3 - "$home" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
index = json.loads((home / "config-profiles-v2/index.json").read_text(encoding="utf-8"))
profiles = []
for directory in (home / "config-profiles-v2/profiles").iterdir():
    if directory.is_dir():
        profiles.append(json.loads((directory / "profile.json").read_text(encoding="utf-8")))
assert len(profiles) == 2
active = next(item for item in profiles if item["id"] == index["active_profile_id"])
assert active["name"] == "beta"
assert (home / "config-profiles/alpha/config.toml").is_file()
assert (home / "config-profiles/beta/config.toml").is_file()
root_config = (home / "config.toml").read_text(encoding="utf-8")
assert "https://beta-2311.example.test/v1" in root_config
assert 'model_reasoning_effort = "xhigh"' in root_config
PY
}

test_failure_rolls_back_managed_and_config() {
  root="$TMP_ROOT/rollback"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p "$home" "$install" "$scripts/lib"
  write_old_catalog "$home/model_catalog.json"
  write_third_party_config \
    "$home/config.toml" "Rollback" "https://rollback.example.test/v1" "xhigh" \
    "$home/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"rollback-secret"}' > "$home/auth.json"
  printf '%s\n' '#!/usr/bin/env sh' 'printf old-binary' > "$install/codex-zh-bin"
  printf '%s\n' '#!/usr/bin/env sh' 'printf old-launcher' > "$install/codex"
  printf '%s\n' old-common > "$scripts/lib/codex-zh-common.sh"
  chmod 755 "$install/codex-zh-bin" "$install/codex"
  before_config="$(sha256_file "$home/config.toml")"

  set +e
  run_upgrade "$home" "$install" "$scripts" \
    env CODEX_APK_UPGRADE_FAILPOINT=after-config-upgrade
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "failure injection unexpectedly succeeded"
  assert_contains "$install/codex-zh-bin" "old-binary"
  assert_contains "$install/codex" "old-launcher"
  assert_contains "$scripts/lib/codex-zh-common.sh" "old-common"
  [ "$before_config" = "$(sha256_file "$home/config.toml")" ] ||
    fail "failed APK upgrade did not restore root config"
  [ ! -e "$home/config-profiles-v2/index.json" ] ||
    fail "failed APK upgrade left V2 state active"
  [ ! -e "$home/install-state/apk-upgrades/2.4.3/complete" ] ||
    fail "failed APK upgrade wrote a completion marker"
}

test_corrupt_state_is_quarantined() {
  root="$TMP_ROOT/corrupt"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p \
    "$home/config-profiles-v2" \
    "$home/install-state" \
    "$home/sessions/2026/07/10" \
    "$install"
  write_old_catalog "$home/model_catalog.json"
  write_third_party_config \
    "$home/config.toml" "Corrupt" "https://corrupt.example.test/v1" "xhigh" \
    "$home/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"corrupt-secret"}' > "$home/auth.json"
  printf '%s\n' '{broken-index' > "$home/config-profiles-v2/index.json"
  printf '%s\n' '{"phase":"prepared","backup":"/missing"}' \
    > "$home/install-state/config-v2-transaction.json"
  printf '%s\n' '{"session":"2.4.0-preserve"}' \
    > "$home/sessions/2026/07/10/preserve.jsonl"
  printf '%s\n' old-shared-sqlite > "$home/state_5.sqlite"
  mkfifo "$home/sessions/2026/07/10/polluted.fifo"

  run_upgrade "$home" "$install" "$scripts"

  python3 - "$home" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
index = json.loads((home / "config-profiles-v2/index.json").read_text(encoding="utf-8"))
assert index["schema_version"] == 2
assert index["active_profile_id"]
profile = json.loads(
    (home / "config-profiles-v2/profiles" / index["active_profile_id"] / "profile.json").read_text(
        encoding="utf-8"
    )
)
runtime = Path(profile["runtime_home"])
assert (runtime / "sessions/2026/07/10/preserve.jsonl").is_file()
assert not (runtime / "sessions/2026/07/10/polluted.fifo").exists()
assert not (runtime / "state_5.sqlite").exists()
assert (home / "state_5.sqlite").is_file()
corrupt = home / "install-state/apk-upgrades/2.4.3/corrupt"
assert any(path.name.startswith("index.json-") for path in corrupt.iterdir())
assert any(path.name.startswith("config-v2-transaction.json-") for path in corrupt.iterdir())
PY
}

test_normal_v2_upgrade_preserves_identity_and_fixed_policy() {
  root="$TMP_ROOT/normal-v2"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p "$home" "$install"

  python3 "$ENGINE" --codex-home "$home" \
    profile create \
    --name stable-v2 \
    --mode third_party \
    --provider-name "Stable V2" \
    --base-url https://stable-v2.example.test/v1 \
    --model gpt-5.6-sol \
    --reasoning-effort xhigh \
    --activate > "$root/create.json"
  python3 "$ENGINE" --codex-home "$home" \
    compact-policy fixed 180000 > "$root/compact.json"
  python3 "$ENGINE" --codex-home "$home" \
    profile launch --sqlite-build-key old-2.4.1-build > "$root/before-launch.json"
  before_id="$(
    python3 - "$root/create.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["profile"]["id"])
PY
  )"
  before_runtime="$(
    python3 - "$root/before-launch.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["runtime_home"])
PY
  )"
  printf '%s\n' old-v2-sqlite > "$before_runtime/sqlite-builds/old-2.4.1-build/state_5.sqlite"
  mkdir -p "$home/sessions/2026/07/10"
  printf '%s\n' '{"session":"detach-old-runtime-link"}' \
    > "$home/sessions/2026/07/10/detach.jsonl"
  printf '%s\n' '{"history":"detach-old-runtime-link"}' > "$home/history.jsonl"
  ln -s "$home/sessions" "$before_runtime/sessions"
  ln -s "$home/history.jsonl" "$before_runtime/history.jsonl"
  mkdir -p "$home/config-profiles/mixed-v1/sessions/2026/07/10"
  write_old_catalog "$home/config-profiles/mixed-v1/model_catalog.json"
  write_third_party_config \
    "$home/config-profiles/mixed-v1/config.toml" "Mixed V1" \
    "https://mixed-v1.example.test/v1" "medium" \
    "$home/config-profiles/mixed-v1/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"mixed-v1-secret"}' \
    > "$home/config-profiles/mixed-v1/auth.json"
  printf '%s\n' '{"session":"mixed-v1-preserve"}' \
    > "$home/config-profiles/mixed-v1/sessions/2026/07/10/mixed.jsonl"

  run_upgrade "$home" "$install" "$scripts"

  python3 - "$home" "$before_id" "$before_runtime" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
before_id = sys.argv[2]
before_runtime = Path(sys.argv[3])
index = json.loads((home / "config-profiles-v2/index.json").read_text(encoding="utf-8"))
assert index["active_profile_id"] == before_id
profile_dir = home / "config-profiles-v2/profiles" / before_id
profile = json.loads((profile_dir / "profile.json").read_text(encoding="utf-8"))
assert profile["compact_policy"] == {"mode": "fixed", "value": 180000}
assert Path(profile["runtime_home"]) == before_runtime
profiles = []
for directory in (home / "config-profiles-v2/profiles").iterdir():
    if directory.is_dir():
        meta = json.loads((directory / "profile.json").read_text(encoding="utf-8"))
        profiles.append(meta)
mixed = next(item for item in profiles if item["name"] == "mixed-v1")
mixed_runtime = Path(mixed["runtime_home"])
assert mixed_runtime != home / "config-profiles/mixed-v1"
assert (mixed_runtime / "sessions/2026/07/10/mixed.jsonl").is_file()
root_config = (home / "config.toml").read_text(encoding="utf-8")
assert "model_auto_compact_token_limit = 180000" in root_config
launch = json.loads(
    (home / "install-state/apk-upgrades/2.4.3/launch-check.json").read_text(encoding="utf-8")
)
assert "apk-2.4.3" in launch["sqlite_home"]
assert "old-2.4.1-build" not in launch["sqlite_home"]
assert (before_runtime / "sqlite-builds/old-2.4.1-build/state_5.sqlite").is_file()
assert not (before_runtime / "sessions").is_symlink()
assert (before_runtime / "sessions/2026/07/10/detach.jsonl").is_file()
assert not (before_runtime / "history.jsonl").is_symlink()
assert (before_runtime / "history.jsonl").is_file()
PY
}

test_v1_runtime_is_unchanged_after_late_rollback() {
  root="$TMP_ROOT/v1-late-rollback"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  legacy="$home/config-profiles/legacy"
  mkdir -p "$legacy" "$install"
  write_old_catalog "$legacy/model_catalog.json"
  write_third_party_config \
    "$legacy/config.toml" "Legacy Rollback" \
    "https://legacy-rollback.example.test/v1" "medium" \
    "$legacy/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"legacy-rollback-secret"}' > "$legacy/auth.json"
  printf '%s\n' legacy > "$home/config-profiles/current"
  before_config="$(sha256_file "$legacy/config.toml")"
  before_catalog="$(sha256_file "$legacy/model_catalog.json")"

  set +e
  run_upgrade "$home" "$install" "$scripts" \
    env CODEX_APK_UPGRADE_FAILPOINT=before-complete
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "late V1 rollback failure injection unexpectedly succeeded"
  [ "$before_config" = "$(sha256_file "$legacy/config.toml")" ] ||
    fail "late rollback modified the original V1 config"
  [ "$before_catalog" = "$(sha256_file "$legacy/model_catalog.json")" ] ||
    fail "late rollback modified the original V1 model catalog"
  [ ! -e "$home/config-profiles-v2/index.json" ] ||
    fail "late rollback left V2 state active"
}

test_missing_binary_is_installed() {
  root="$TMP_ROOT/missing-binary"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p "$home/install-state" "$install"
  printf '%s\n' official > "$home/install-state/official-login-mode"
  [ ! -e "$install/codex-zh-bin" ] || fail "missing-binary fixture is invalid"

  run_upgrade "$home" "$install" "$scripts"

  [ -x "$install/codex-zh-bin" ] || fail "missing Codex binary was not installed"
  [ -x "$install/codex" ] || fail "launcher was not installed with missing binary"
  assert_contains "$home/install-state/apk-upgrades/2.4.3/complete" "version_code=58"
}

test_stale_empty_lock_is_recovered() {
  root="$TMP_ROOT/stale-lock"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p "$home/install-state/apk-upgrade.lock" "$install"
  printf '%s\n' official > "$home/install-state/official-login-mode"

  run_upgrade "$home" "$install" "$scripts" \
    env CODEX_APK_UPGRADE_LOCK_WAIT_SECONDS=5

  [ -s "$home/install-state/apk-upgrades/2.4.3/complete" ] ||
    fail "stale lock recovery did not complete the upgrade"
  [ ! -d "$home/install-state/apk-upgrade.lock" ] ||
    fail "stale lock recovery left the lock behind"
}

test_concurrent_upgrade_is_serialized() {
  root="$TMP_ROOT/concurrent"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  mkdir -p "$home" "$install"
  write_old_catalog "$home/model_catalog.json"
  write_third_party_config \
    "$home/config.toml" "Concurrent" "https://concurrent.example.test/v1" "xhigh" \
    "$home/model_catalog.json"
  printf '%s\n' '{"OPENAI_API_KEY":"concurrent-secret"}' > "$home/auth.json"

  run_upgrade "$home" "$install" "$scripts" \
    env CODEX_APK_UPGRADE_TEST_HOLD_SECONDS=1 > "$root/first.out" 2> "$root/first.err" &
  first_pid=$!
  run_upgrade "$home" "$install" "$scripts" \
    env CODEX_APK_UPGRADE_TEST_HOLD_SECONDS=1 > "$root/second.out" 2> "$root/second.err" &
  second_pid=$!
  wait "$first_pid"
  wait "$second_pid"
  [ -s "$home/install-state/apk-upgrades/2.4.3/complete" ] ||
    fail "concurrent upgrade did not complete"
  [ ! -d "$home/install-state/apk-upgrade.lock" ] ||
    fail "concurrent upgrade left the lock behind"
  python3 "$ENGINE" --codex-home "$home" status > "$root/status.json"
  python3 - "$root/status.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
assert value["schema_version"] == 2
assert value["profile_count"] == 1
PY
}

test_corrupt_payload_is_rejected_before_install() {
  root="$TMP_ROOT/bad-payload"
  home="$root/root/.codex"
  install="$root/usr/local/bin"
  scripts="$root/root/.local/share/codex-zh/scripts"
  bad_payload="$root/payload"
  mkdir -p "$home" "$install" "$bad_payload"
  cp "$TMP_ROOT/payload"/* "$bad_payload/"
  printf '%s\n' corrupt >> "$bad_payload/codex-test-0.144.1.tgz"
  printf '%s\n' '#!/usr/bin/env sh' 'printf old' > "$install/codex"
  chmod 755 "$install/codex"

  set +e
  HOME="$root/root" \
  CODEX_HOME="$home" \
  CODEX_APK_UPGRADE_CODEX_HOME="$home" \
  CODEX_APK_UPGRADE_INSTALL_DIR="$install" \
  CODEX_APK_UPGRADE_SCRIPT_ROOT="$scripts" \
  CODEX_APK_UPGRADE_ASSET_DIR="$bad_payload" \
  CODEX_APK_UPGRADE_ALLOW_TEST_PAYLOAD=1 \
  CODEX_APK_UPGRADE_SKIP_REFRESH=1 \
    sh "$UPGRADER" > "$root/stdout" 2> "$root/stderr"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "corrupt payload unexpectedly succeeded"
  assert_contains "$install/codex" "old"
  [ ! -e "$home/install-state/apk-upgrades/2.4.3/complete" ] ||
    fail "corrupt payload wrote a completion marker"
}

sh -n "$UPGRADER"
prepare_test_payload
printf 'RUN 2.3.11 V1-only APK upgrade\n'
test_2311_v1_only_upgrade
printf 'RUN real 2.4.1 fault-state APK upgrade\n'
test_real_241_fault_upgrade
printf 'RUN APK upgrade rollback\n'
test_failure_rolls_back_managed_and_config
printf 'RUN 2.4.0 interrupted/polluted state recovery\n'
test_corrupt_state_is_quarantined
printf 'RUN normal V2 identity and fixed-policy upgrade\n'
test_normal_v2_upgrade_preserves_identity_and_fixed_policy
printf 'RUN late V1 rollback preserves original profile\n'
test_v1_runtime_is_unchanged_after_late_rollback
printf 'RUN missing binary replacement\n'
test_missing_binary_is_installed
printf 'RUN stale empty APK upgrade lock recovery\n'
test_stale_empty_lock_is_recovered
printf 'RUN concurrent APK upgrade serialization\n'
test_concurrent_upgrade_is_serialized
printf 'RUN corrupt APK payload rejection\n'
test_corrupt_payload_is_rejected_before_install
printf 'OK: Codex for TUI APK upgrade smoke tests passed\n'
