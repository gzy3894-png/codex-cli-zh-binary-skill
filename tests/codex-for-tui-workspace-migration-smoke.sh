#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MIGRATOR="$ROOT_DIR/android-arm64-musl/libexec/codex-workspace-migrate.py"
AUDITOR="$ROOT_DIR/tests/codex-for-tui-workspace-history-audit.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-workspace-migration.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

prepare_fixture() {
  home="$1"
  python3 - "$home" <<'PY'
import json
import os
import shutil
import sqlite3
import sys
from pathlib import Path

home = Path(sys.argv[1])
sessions = home / "sessions/2026/07/02"
sessions.mkdir(parents=True)
old = sessions / "rollout-old.jsonl"
current = sessions / "rollout-current.jsonl"
first = {
    "timestamp": "2026-07-02T00:00:00Z",
    "type": "session_meta",
    "payload": {
        "session_id": "019f212d-4b6e-7e93-b3f4-188eefa2657d",
        "id": "019f212d-4b6e-7e93-b3f4-188eefa2657d",
        "cwd": "/root",
        "base_instructions": {"text": "keep cwd text /root unchanged"},
    },
}
tail = (
    json.dumps({"type": "message", "cwd": "/root", "text": "body-must-not-change"})
    + "\n"
    + ("x" * (2 * 1024 * 1024))
    + "\n"
).encode()
old.write_bytes(
    json.dumps(first, ensure_ascii=False, separators=(",", ":")).encode() + b"\n" + tail
)
current.write_text(
    json.dumps(
        {
            "type": "session_meta",
            "payload": {
                "session_id": "019f5475-085a-7f81-8d96-2b8c3a57e397",
                "cwd": "/root/workspace",
            },
        },
        separators=(",", ":"),
    )
    + "\n",
    encoding="utf-8",
)
legacy_root = (
    home
    / "config-runtimes/p-legacy/sessions/2026/07/10"
)
legacy_root.mkdir(parents=True)
legacy = legacy_root / "rollout-legacy-root.jsonl"
legacy_first = {
    "type": "session_meta",
    "payload": {
        "session_id": "019f4d07-3b27-7870-8a20-a97580adbdd2",
        "id": "019f4d07-3b27-7870-8a20-a97580adbdd2",
        "cwd": "/root",
        "model_provider": "custom",
    },
}
legacy.write_text(
    json.dumps(legacy_first, separators=(",", ":"))
    + "\n"
    + json.dumps({"type": "message", "text": "legacy-body-must-not-change"})
    + "\n",
    encoding="utf-8",
)
legacy_duplicate = (
    home
    / "config-profiles/legacy/sessions/2026/07/10"
    / legacy.name
)
legacy_duplicate.parent.mkdir(parents=True)
shutil.copy2(legacy, legacy_duplicate)
legacy_workspace = (
    home
    / "config-runtimes/p-legacy/sessions/2026/07/11"
    / "rollout-legacy-workspace.jsonl"
)
legacy_workspace.parent.mkdir(parents=True)
legacy_workspace.write_text(
    json.dumps(
        {
            "type": "session_meta",
            "payload": {
                "session_id": "019f518d-7fac-7581-afe7-a47e893ffa0e",
                "id": "019f518d-7fac-7581-afe7-a47e893ffa0e",
                "cwd": "/root/workspace",
                "model_provider": "custom",
            },
        },
        separators=(",", ":"),
    )
    + "\n",
    encoding="utf-8",
)
fixed_ns = 1_782_968_404_123_456_789
os.utime(old, ns=(fixed_ns, fixed_ns))
os.utime(legacy, ns=(fixed_ns, fixed_ns))
os.utime(legacy_duplicate, ns=(fixed_ns, fixed_ns))
os.utime(legacy_workspace, ns=(fixed_ns, fixed_ns))

def make_db(path: Path, rows: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT, title TEXT)")
    db.executemany(
        "INSERT INTO threads(id, cwd, title) VALUES (?, ?, 'preserve')", rows
    )
    db.commit()
    db.close()

make_db(
    home / "state_5.sqlite",
    [
        ("019f212d-4b6e-7e93-b3f4-188eefa2657d", "/root"),
        ("019f5475-085a-7f81-8d96-2b8c3a57e397", "/root/workspace"),
    ],
)
make_db(
    home
    / "config-runtimes/p-0123456789ab/sqlite-builds/test-build/state_5.sqlite",
    [
        ("019f212d-4b6e-7e93-b3f4-188eefa2657d", "/root"),
        ("019f4d07-3b27-7870-8a20-a97580adbdd2", "/root"),
    ],
)
PY
}

assert_state() {
  home="$1"
  expected="$2"
  imported="$3"
  python3 - "$home" "$expected" "$imported" <<'PY'
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

home = Path(sys.argv[1])
expected = sys.argv[2]
imported = sys.argv[3] == "present"
old = home / "sessions/2026/07/02/rollout-old.jsonl"
with old.open("rb") as handle:
    first = json.loads(handle.readline())
    tail_hash = hashlib.sha256(handle.read()).hexdigest()
assert first["payload"]["cwd"] == expected
assert first["payload"]["base_instructions"]["text"] == "keep cwd text /root unchanged"
assert tail_hash == "9c71bbcb86ef4feefcddaa2908c3c0f019c869bcd764bf54b1fcb4651c36f8ad"
assert old.stat().st_mtime_ns == 1_782_968_404_123_456_789
legacy_source = (
    home
    / "config-runtimes/p-legacy/sessions/2026/07/10/rollout-legacy-root.jsonl"
)
legacy_duplicate = (
    home
    / "config-profiles/legacy/sessions/2026/07/10/rollout-legacy-root.jsonl"
)
with legacy_source.open("rb") as handle:
    legacy_source_bytes = handle.read()
assert legacy_source_bytes == legacy_duplicate.read_bytes()
assert json.loads(legacy_source_bytes.splitlines()[0])["payload"]["cwd"] == "/root"
legacy_import = home / "sessions/2026/07/10/rollout-legacy-root.jsonl"
workspace_import = home / "sessions/2026/07/11/rollout-legacy-workspace.jsonl"
assert legacy_import.exists() is imported
assert workspace_import.exists() is imported
if imported:
    with legacy_import.open("rb") as handle:
        imported_first = json.loads(handle.readline())
        imported_tail = handle.read()
    assert imported_first["payload"]["cwd"] == expected
    assert imported_first["payload"]["session_id"] == (
        "019f4d07-3b27-7870-8a20-a97580adbdd2"
    )
    assert imported_tail == b'{"type": "message", "text": "legacy-body-must-not-change"}\n'
    assert legacy_import.stat().st_mtime_ns == 1_782_968_404_123_456_789
    with workspace_import.open(encoding="utf-8") as handle:
        workspace_first = json.loads(handle.readline())
    assert workspace_first["payload"]["cwd"] == "/root/workspace"
    assert workspace_import.stat().st_mtime_ns == 1_782_968_404_123_456_789
for path in (
    home / "state_5.sqlite",
    home
    / "config-runtimes/p-0123456789ab/sqlite-builds/test-build/state_5.sqlite",
):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    values = {
        row[0]
        for row in db.execute(
            "SELECT cwd FROM threads WHERE id = ?",
            ("019f212d-4b6e-7e93-b3f4-188eefa2657d",),
        )
    }
    db.close()
    assert values == {expected}, (path, values)
runtime_db = sqlite3.connect(
    home
    / "config-runtimes/p-0123456789ab/sqlite-builds/test-build/state_5.sqlite"
)
legacy_values = {
    row[0]
    for row in runtime_db.execute(
        "SELECT cwd FROM threads WHERE id = ?",
        ("019f4d07-3b27-7870-8a20-a97580adbdd2",),
    )
}
runtime_db.close()
assert legacy_values == {expected}
PY
}

home="$TMP_ROOT/success/root/.codex"
prepare_fixture "$home"
python3 "$AUDITOR" snapshot --codex-home "$home" > "$TMP_ROOT/baseline.json"
python3 "$MIGRATOR" --codex-home "$home" migrate \
  --from /root --to /root/workspace --release 2.5.12 \
  --import-legacy-runtimes > "$TMP_ROOT/migrate.json"
assert_state "$home" /root/workspace present
grep -F '"import_count": 2' "$TMP_ROOT/migrate.json" >/dev/null ||
  fail "legacy rollout import count mismatch"
grep -F '"rollout_count": 2' "$TMP_ROOT/migrate.json" >/dev/null ||
  fail "workspace rollout count mismatch"
python3 "$AUDITOR" verify \
  --codex-home "$home" \
  --release-report "$TMP_ROOT/migrate.json" \
  --baseline "$TMP_ROOT/baseline.json" \
  --release 2.5.12 \
  --expected-import-count 2 \
  --expected-migrated-count 2 \
  --expected-baseline-count 2 \
  --expected-min-count 4 > "$TMP_ROOT/audit.json"
grep -F '"ok": true' "$TMP_ROOT/audit.json" >/dev/null ||
  fail "post-migration history audit failed"

backup="$(
  python3 - "$TMP_ROOT/migrate.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["backup"])
PY
)"
[ -s "$backup/manifest.json" ] || fail "migration backup manifest missing"
grep -F '"imports": [' "$backup/manifest.json" >/dev/null ||
  fail "migration backup manifest missing imports"
python3 "$MIGRATOR" --codex-home "$home" migrate \
  --from /root --to /root/workspace --release 2.5.12 \
  --import-legacy-runtimes > "$TMP_ROOT/idempotent.json"
grep -F '"already_migrated": true' "$TMP_ROOT/idempotent.json" >/dev/null ||
  fail "second migration was not idempotent"
python3 "$MIGRATOR" --codex-home "$home" rollback --backup "$backup" \
  > "$TMP_ROOT/rollback.json"
assert_state "$home" /root absent

set +e
CODEX_WORKSPACE_MIGRATION_FAILPOINT=after-sqlite \
  python3 "$MIGRATOR" --codex-home "$home" migrate \
  --from /root --to /root/workspace --release 2.5.12 \
  --import-legacy-runtimes > "$TMP_ROOT/failpoint.json"
rc=$?
set -e
[ "$rc" -eq 86 ] || fail "transaction failpoint returned $rc"
assert_state "$home" /root absent
[ ! -e "$home/install-state/workspace-migration.json" ] ||
  fail "handled failure left migration journal"

crash_home="$TMP_ROOT/crash/root/.codex"
prepare_fixture "$crash_home"
set +e
CODEX_WORKSPACE_MIGRATION_FAILPOINT=crash:after-imports \
  python3 "$MIGRATOR" --codex-home "$crash_home" migrate \
  --from /root --to /root/workspace --release 2.5.12 \
  --import-legacy-runtimes > "$TMP_ROOT/crash.json"
rc=$?
set -e
[ "$rc" -eq 86 ] || fail "crash failpoint returned $rc"
[ -s "$crash_home/install-state/workspace-migration.json" ] ||
  fail "crash did not leave recovery journal"
python3 "$MIGRATOR" --codex-home "$crash_home" migrate \
  --from /root --to /root/workspace --release 2.5.12 \
  --import-legacy-runtimes > "$TMP_ROOT/recovered.json"
grep -F '"recovered_transaction": true' "$TMP_ROOT/recovered.json" >/dev/null ||
  fail "crash recovery was not reported"
assert_state "$crash_home" /root/workspace present

compat_home="$TMP_ROOT/compat/root/.codex"
prepare_fixture "$compat_home"
python3 "$AUDITOR" snapshot --codex-home "$compat_home" \
  > "$TMP_ROOT/compat-baseline.json"
python3 "$MIGRATOR" --codex-home "$compat_home" migrate \
  --from /root --to /root/workspace --release 2.5.12 \
  --import-legacy-runtimes > "$TMP_ROOT/compat-migrate.json"
compat_completion="$compat_home/install-state/workspace-migrations/2.5.12.json"
[ -s "$compat_completion" ] ||
  fail "durable migration completion report missing"
python3 - "$compat_home" <<'PY'
import os
import shutil
import sys
from pathlib import Path

home = Path(sys.argv[1])
rollout = home / "sessions/2026/07/02/rollout-old.jsonl"
rollout.chmod(0o600)
current = rollout.stat()
os.utime(
    rollout,
    ns=(current.st_atime_ns, current.st_mtime_ns + 1_000_000_000),
)
shutil.rmtree(home / "config-profiles/legacy/sessions")
PY
python3 "$AUDITOR" verify \
  --codex-home "$compat_home" \
  --release-report "$compat_completion" \
  --baseline "$TMP_ROOT/compat-baseline.json" \
  --release 2.5.12 \
  --expected-import-count 2 \
  --expected-migrated-count 2 \
  --expected-baseline-count 2 \
  --expected-min-count 4 > "$TMP_ROOT/compat-audit.json"
grep -F '"ok": true' "$TMP_ROOT/compat-audit.json" >/dev/null ||
  fail "completion fallback and hardened metadata audit failed"
chmod 0664 "$compat_home/sessions/2026/07/02/rollout-old.jsonl"
set +e
python3 "$AUDITOR" verify \
  --codex-home "$compat_home" \
  --release-report "$compat_completion" \
  --baseline "$TMP_ROOT/compat-baseline.json" \
  --release 2.5.12 \
  --expected-import-count 2 \
  --expected-migrated-count 2 \
  --expected-baseline-count 2 \
  --expected-min-count 4 > "$TMP_ROOT/compat-broadened-mode.json"
rc=$?
set -e
[ "$rc" -ne 0 ] ||
  fail "history audit accepted broadened rollout permissions"
grep -F 'rollout permission mode changed' "$TMP_ROOT/compat-broadened-mode.json" >/dev/null ||
  fail "broadened rollout permission failure was not reported"

printf '%s\n' "codex workspace migration smoke: PASS"
