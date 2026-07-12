#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APK="${1:-}"
EXPECTED_RELEASE="${CODEX_TUI_EXPECTED_VERSION_NAME:-2.5.13}"
EXPECTED_VERSION_CODE="${CODEX_TUI_EXPECTED_VERSION_CODE:-78}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

manifest_value() {
  key="$1"
  sed -n "s/^${key}=//p" "$work/manifest.properties" | sed -n '1p'
}

[ -n "$APK" ] || fail "usage: $0 APK"
[ -r "$APK" ] || fail "APK not found: $APK"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

work="$(mktemp -d "${TMPDIR:-/tmp}/codex-apk-inspect.XXXXXX")"
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

for asset in \
  assets/codex-apk-upgrade.sh \
  assets/codex-upgrade/manifest.properties \
  assets/codex-upgrade/manifest.sha256
do
  unzip -p "$APK" "$asset" > "$work/$(basename "$asset")" ||
    fail "APK is missing $asset"
  [ -s "$work/$(basename "$asset")" ] || fail "APK asset is empty: $asset"
done

cmp "$work/codex-apk-upgrade.sh" "$ROOT_DIR/android-arm64-musl/codex-apk-upgrade.sh" >/dev/null 2>&1 ||
  fail "APK upgrader differs from canonical source"

expected_manifest_sha="$(
  awk 'NF { print tolower($1); exit }' "$work/manifest.sha256"
)"
[ -n "$expected_manifest_sha" ] || fail "manifest.sha256 is empty"
[ "$(sha256_file "$work/manifest.properties")" = "$expected_manifest_sha" ] ||
  fail "manifest.properties SHA256 mismatch"

[ "$(manifest_value schema_version)" = "1" ] || fail "unexpected payload schema"
[ "$(manifest_value release)" = "$EXPECTED_RELEASE" ] ||
  fail "payload release does not match $EXPECTED_RELEASE"
[ "$(manifest_value version_code)" = "$EXPECTED_VERSION_CODE" ] ||
  fail "payload versionCode does not match $EXPECTED_VERSION_CODE"
[ "$(manifest_value codex_version)" = "0.144.1" ] || fail "unexpected Codex version"
[ "$(manifest_value target)" = "aarch64-unknown-linux-musl" ] || fail "unexpected Codex target"
[ "$(manifest_value runtime_epoch)" = "apk-2.5.13" ] || fail "unexpected runtime epoch"

support_archive="$(manifest_value support_archive)"
binary_archive="$(manifest_value binary_archive)"
case "$support_archive" in
  ""|*/*|*..*) fail "unsafe support archive name: $support_archive" ;;
  *.gz) fail "support archive uses an AAPT-unsafe .gz asset suffix" ;;
esac
case "$binary_archive" in
  ""|*/*|*..*) fail "unsafe binary archive name: $binary_archive" ;;
  *.gz) fail "binary archive uses an AAPT-unsafe .gz asset suffix" ;;
esac

unzip -p "$APK" "assets/codex-upgrade/$support_archive" > "$work/$support_archive" ||
  fail "APK is missing support archive"
unzip -p "$APK" "assets/codex-upgrade/$binary_archive" > "$work/$binary_archive" ||
  fail "APK is missing binary archive"

[ "$(sha256_file "$work/$support_archive")" = "$(manifest_value support_sha256)" ] ||
  fail "support archive SHA256 mismatch"
[ "$(sha256_file "$work/$binary_archive")" = "$(manifest_value binary_archive_sha256)" ] ||
  fail "binary archive SHA256 mismatch"
[ "$(manifest_value binary_archive_sha256)" = "1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61" ] ||
  fail "binary archive is not the fixed 0.144.1-zh.1 artifact"

support_count="$(
  tar -tzf "$work/$support_archive" |
    awk '!/\/$/ { count += 1 } END { print count + 0 }'
)"
[ "$support_count" = "$(manifest_value support_file_count)" ] ||
  fail "support archive file count mismatch"
for member in \
  ./codex-apk-upgrade.sh \
  ./lib/codex-zh-common.sh \
  ./lib/codex-zh-local.sh \
  ./libexec/codex-config-engine.py \
  ./libexec/codex-workspace-migrate.py \
  ./data/openai-models.json
do
  tar -tzf "$work/$support_archive" | grep -F -x "$member" >/dev/null 2>&1 ||
    fail "support archive is missing $member"
done

binary_member="codex-0.144.1-zh-aarch64-unknown-linux-musl"
tar -xzf "$work/$binary_archive" -C "$work" "$binary_member" ||
  fail "fixed Codex binary is missing from archive"
[ "$(sha256_file "$work/$binary_member")" = "$(manifest_value binary_sha256)" ] ||
  fail "fixed Codex binary SHA256 mismatch"
[ "$(manifest_value binary_sha256)" = "0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767" ] ||
  fail "unexpected fixed Codex binary"

apk_size="$(wc -c < "$APK" | tr -d ' ')"
[ "$apk_size" -gt 75000000 ] || fail "APK is too small to contain the fixed offline payload"

printf 'OK: APK Codex payload verified\n'
printf 'apk=%s\n' "$APK"
printf 'release=%s versionCode=%s runtimeEpoch=%s\n' \
  "$(manifest_value release)" \
  "$(manifest_value version_code)" \
  "$(manifest_value runtime_epoch)"
printf 'archive_sha256=%s\n' "$(manifest_value binary_archive_sha256)"
printf 'binary_sha256=%s\n' "$(manifest_value binary_sha256)"
