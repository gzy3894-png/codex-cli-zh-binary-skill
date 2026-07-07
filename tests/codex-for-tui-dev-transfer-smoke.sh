#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TRANSFER_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-dev-transfer"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
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
    fail "$label should not contain: $needle"
  fi
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || {
    [ ! -r "$file" ] || sed -n '1,120p' "$file" >&2 || true
    fail "expected pattern not found in $file: $pattern"
  }
}

assert_path_absent() {
  path="$1"
  [ ! -e "$path" ] || fail "path should be absent: $path"
}

assert_file_not_contains() {
  file="$1"
  pattern="$2"
  if grep -F -- "$pattern" "$file" >/dev/null 2>&1; then
    [ ! -r "$file" ] || sed -n '1,160p' "$file" >&2 || true
    fail "unexpected pattern found in $file: $pattern"
  fi
}

sh -n "$TRANSFER_ASSET" || fail "codex-dev-transfer shell syntax failed"

tmp="${TMPDIR:-/tmp}/codex-tui-dev-transfer-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/export-home/.codex/sessions" \
  "$tmp/export-home/.codex/.tmp/plugins/.git/objects/pack" \
  "$tmp/export-home/.codex/.tmp/plugins-clone-fixture/.git/objects/pack" \
  "$tmp/export-home/.codex-for-tui" \
  "$tmp/export-home/.local/bin" "$tmp/export-home/.local/share/codex-zh" \
  "$tmp/export-home/.cache/codex-zh/scripts/lib" "$tmp/export-prefix/shared_prefs" \
  "$tmp/export-prefix/files" "$tmp/export-prefix/databases" "$tmp/export-prefix/app_webview" \
  "$tmp/export-prefix/no_backup" "$tmp/export-prefix/local/bin" \
  "$tmp/export-prefix/local/browser" "$tmp/export-prefix/local/media-preview" \
  "$tmp/export-prefix/local/agent-panel" "$tmp/export-prefix/local/session-fold" \
  "$tmp/export-prefix/local/perf" "$tmp/export-prefix/local/ops" \
  "$tmp/import-home" "$tmp/import-prefix" "$tmp/snapshots"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cp "$TRANSFER_ASSET" "$tmp/bin/codex-dev-transfer"
chmod 755 "$tmp/bin/codex-dev-transfer"

old_pkg="com.gzy3894.codexfortui"
new_pkg="com.gzy3894.codexfortui.test"
old_prefix="/data/user/0/$old_pkg"
new_prefix="/data/user/0/$new_pkg"
export_fs_prefix="$tmp/export-prefix"
import_fs_prefix="$tmp/import-prefix"

cat > "$tmp/export-home/.codex/config.toml" <<EOF
model_provider = "custom"
cwd = "$old_prefix/files/home"
package = "$old_pkg"
EOF

cat > "$tmp/export-home/.codex/sessions/session.jsonl" <<EOF
{"cwd":"$old_prefix/files/home","pkg":"$old_pkg","data":"/data/data/$old_pkg/files"}
EOF

cat > "$tmp/export-home/.codex/auth.json" <<'EOF'
{"OPENAI_API_KEY":"sk-dev-transfer-smoke-secret"}
EOF
printf 'transient plugin pack cache\n' > "$tmp/export-home/.codex/.tmp/plugins-clone-fixture/.git/objects/pack/.l2s.tmp_pack_fixture.0001"
ln -s "$tmp/export-home/.codex/.tmp/plugins-clone-fixture/.git/objects/pack/.l2s.tmp_pack_fixture.0001" \
  "$tmp/export-home/.codex/.tmp/plugins/.git/objects/pack/pack-fixture.pack" 2>/dev/null || true

cat > "$tmp/export-home/.local/bin/codex" <<'EOF'
#!/usr/bin/env sh
printf 'codex fixture\n'
EOF
chmod 755 "$tmp/export-home/.local/bin/codex"
printf 'share fixture\n' > "$tmp/export-home/.local/share/codex-zh/readme.txt"
printf 'cache fixture\n' > "$tmp/export-home/.cache/codex-zh/scripts/lib/cache.txt"
printf 'consent fixture\n' > "$tmp/export-home/.codex-for-tui/install-consent"
printf '<map><string name="prefix">%s</string></map>\n' "$old_prefix" > "$tmp/export-prefix/shared_prefs/settings.xml"
printf 'user file fixture\n' > "$tmp/export-prefix/files/user.txt"
printf 'OPENAI_API_KEY=sk-dev-transfer-smoke-secret\n' > "$tmp/export-prefix/files/secret.env"
printf 'cookie fixture\n' > "$tmp/export-prefix/app_webview/Cookies"
printf 'db fixture\n' > "$tmp/export-prefix/databases/browser.db"
printf 'token fixture\n' > "$tmp/export-prefix/no_backup/token.txt"
printf 'browser=%s\n' "$old_pkg" > "$tmp/export-prefix/local/browser/status"
printf 'ops=%s\napp=%s\n' "$old_prefix" "$export_fs_prefix" > "$tmp/export-prefix/local/ops/status"

export HOME="$tmp/export-home"
export CODEX_HOME="$tmp/export-home/.codex"
export PREFIX="$export_fs_prefix"
export PKG="$old_pkg"
export PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}"
export CODEX_DEV_TRANSFER_DIR="$tmp/snapshots"
export CODEX_DEV_TRANSFER_INCLUDE_SYSTEM=0

doctor_json="$(codex-dev-transfer doctor --json 2>&1)" || fail "doctor --json failed"
assert_contains "$doctor_json" '"ok":true' "doctor json"
assert_contains "$doctor_json" "\"package\":\"$old_pkg\"" "doctor json"

export_output="$(codex-dev-transfer export smoke 2>&1)" || fail "export failed"
assert_contains "$export_output" "已导出开发者迁移包" "export output"
snapshot="$(ls -t "$tmp/snapshots"/codex-dev-transfer-smoke-*.tar.gz 2>/dev/null | sed -n '1p')"
[ -s "$snapshot" ] || fail "snapshot was not created"
tar -tzf "$snapshot" > "$tmp/default-snapshot.list"
assert_file_contains "$tmp/default-snapshot.list" 'manifest.txt'
assert_file_contains "$tmp/default-snapshot.list" 'payload/root/.codex/config.toml'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/root/.codex/auth.json'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/root/.codex/.tmp/'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/root/.codex/sessions/'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/app/app_webview/'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/app/databases/'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/app/no_backup/'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/app/local/browser/'
assert_file_not_contains "$tmp/default-snapshot.list" 'payload/app/files/secret.env'

verify_json="$(codex-dev-transfer verify --json "$snapshot" 2>&1)" || fail "verify --json failed"
assert_contains "$verify_json" '"ok":true' "verify json"

rollback_snapshot="$tmp/snapshots/codex-dev-transfer-rollback-smoke-newer.tar.gz"
cp "$snapshot" "$rollback_snapshot"
touch "$rollback_snapshot" 2>/dev/null || true
latest_json="$(codex-dev-transfer verify --json latest 2>&1)" || fail "verify latest failed"
assert_contains "$latest_json" "\"file\":\"$snapshot\"" "verify latest json"
rollback_json="$(codex-dev-transfer verify --json rollback-latest 2>&1)" || fail "verify rollback-latest failed"
assert_contains "$rollback_json" "\"file\":\"$rollback_snapshot\"" "verify rollback-latest json"

list_json="$(codex-dev-transfer list --json 2>&1)" || fail "list --json failed"
assert_contains "$list_json" '"snapshot_dir":' "list json"
assert_contains "$list_json" 'codex-dev-transfer-smoke-' "list json"

export HOME="$tmp/import-home"
export CODEX_HOME="$tmp/import-home/.codex"
export PREFIX="$import_fs_prefix"
export PKG="$new_pkg"
mkdir -p "$import_fs_prefix"

import_output="$(codex-dev-transfer import --yes --no-backup "$snapshot" 2>&1)" || fail "import failed"
assert_contains "$import_output" "导入完成" "import output"

assert_file_contains "$tmp/import-home/.codex/config.toml" "$new_prefix/files/home"
assert_file_contains "$tmp/import-home/.codex/config.toml" "$new_pkg"
[ ! -e "$tmp/import-home/.codex/sessions/session.jsonl" ] || fail "default import should not restore Codex session history"
assert_file_contains "$import_fs_prefix/shared_prefs/settings.xml" "$new_prefix"
[ ! -e "$import_fs_prefix/local/browser/status" ] || fail "default import should not restore browser login state"
assert_file_contains "$import_fs_prefix/local/ops/status" "$import_fs_prefix"
assert_file_contains "$import_fs_prefix/local/ops/status" "$new_prefix"
[ -x "$tmp/import-home/.local/bin/codex" ] || fail "imported codex launcher is not executable"
[ ! -e "$tmp/import-home/.codex/auth.json" ] || fail "default import should not restore auth.json"
assert_file_contains "$tmp/import-home/.local/share/codex-zh/readme.txt" "share fixture"
assert_file_contains "$tmp/import-home/.cache/codex-zh/scripts/lib/cache.txt" "cache fixture"
assert_file_contains "$tmp/import-home/.codex-for-tui/install-consent" "consent fixture"

export HOME="$tmp/export-home"
export CODEX_HOME="$tmp/export-home/.codex"
export PREFIX="$export_fs_prefix"
export PKG="$old_pkg"

secret_output="$(codex-dev-transfer export --include-secrets --yes smoke-secret 2>&1)" || fail "include-secrets export failed"
assert_contains "$secret_output" "敏感导出已启用" "include-secrets output"
secret_snapshot="$(ls -t "$tmp/snapshots"/codex-dev-transfer-smoke-secret-*.tar.gz 2>/dev/null | sed -n '1p')"
[ -s "$secret_snapshot" ] || fail "include-secrets snapshot was not created"
tar -tzf "$secret_snapshot" > "$tmp/secret-snapshot.list"
assert_file_contains "$tmp/secret-snapshot.list" 'payload/root/.codex/auth.json'
assert_file_not_contains "$tmp/secret-snapshot.list" 'payload/root/.codex/.tmp/'
assert_file_contains "$tmp/secret-snapshot.list" 'payload/root/.codex/sessions/'
assert_file_contains "$tmp/secret-snapshot.list" 'payload/app/app_webview/'
assert_file_contains "$tmp/secret-snapshot.list" 'payload/app/databases/'
assert_file_contains "$tmp/secret-snapshot.list" 'payload/app/no_backup/'
assert_file_contains "$tmp/secret-snapshot.list" 'payload/app/local/browser/'
assert_file_contains "$tmp/secret-snapshot.list" 'payload/app/files/secret.env'
codex-dev-transfer verify "$secret_snapshot" >/dev/null || fail "include-secrets verify failed"

export HOME="$tmp/import-secret-home"
export CODEX_HOME="$tmp/import-secret-home/.codex"
export PREFIX="$tmp/import-secret-prefix"
export PKG="$new_pkg"
mkdir -p "$PREFIX"
import_secret_output="$(codex-dev-transfer import --yes --no-backup "$secret_snapshot" 2>&1)" || fail "include-secrets import failed"
assert_contains "$import_secret_output" "导入完成" "include-secrets import output"
[ -s "$tmp/import-secret-home/.codex/auth.json" ] || fail "include-secrets import should restore auth.json"
assert_file_contains "$tmp/import-secret-home/.codex/sessions/session.jsonl" "$new_prefix/files/home"
assert_file_contains "$tmp/import-secret-prefix/local/browser/status" "$new_pkg"

mkdir -p "$tmp/evil/payload/root/.codex"
printf 'format=codex-dev-transfer-v1\ninclude_secrets=0\n' > "$tmp/evil/manifest.txt"
printf 'bad\n' > "$tmp/evil/evil.txt"
(cd "$tmp/evil" && tar -czf "$tmp/evil-unknown.tar.gz" manifest.txt evil.txt)
if codex-dev-transfer verify "$tmp/evil-unknown.tar.gz" >/dev/null 2>&1; then
  fail "verify should reject unknown top-level tar member"
fi
ln -s /tmp "$tmp/evil/payload/root/.codex/link-out"
(cd "$tmp/evil" && tar -czf "$tmp/evil-link.tar.gz" manifest.txt payload)
if codex-dev-transfer verify "$tmp/evil-link.tar.gz" >/dev/null 2>&1; then
  fail "verify should reject symlink tar member"
fi

printf 'OK: Codex for TUI dev transfer smoke passed\n'
