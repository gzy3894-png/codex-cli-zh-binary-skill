#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
OUTPUT_DIR="${CODEX_TUI_PAYLOAD_OUTPUT_DIR:-$ROOT_DIR/android-app/core/main/src/main/assets/codex-upgrade}"
ASSET_ROOT="$(dirname "$OUTPUT_DIR")"
ARCHIVE="${CODEX_TUI_BINARY_ARCHIVE:-${1:-/root/.cache/codex-zh/codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz}}"
RELEASE="2.5.14"
VERSION_CODE="80"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/codex-zh-common.sh"

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

fail() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

[ -r "$ARCHIVE" ] || fail "找不到 Codex 固定归档：$ARCHIVE"
[ "$(sha256_file "$ARCHIVE")" = "$(printf '%s' "$CODEX_ZH_ARCHIVE_SHA256" | tr '[:upper:]' '[:lower:]')" ] ||
  fail "Codex 固定归档 SHA256 不匹配：$ARCHIVE"

work="$(mktemp -d "${TMPDIR:-/tmp}/codex-apk-payload.XXXXXX")"
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

support_root="$work/support"
binary_root="$work/binary"
mkdir -p "$support_root" "$binary_root"

while IFS= read -r relative; do
  [ -n "$relative" ] || continue
  source_file="$SCRIPT_DIR/$relative"
  [ -r "$source_file" ] || fail "APK 支持载荷缺少：$relative"
  mkdir -p "$support_root/$(dirname "$relative")"
  cp "$source_file" "$support_root/$relative"
  chmod "$(codex_support_file_mode "$relative")" "$support_root/$relative"
done <<EOF
$(codex_support_file_list)
EOF

tar -xzf "$ARCHIVE" -C "$binary_root"
binary=""
for candidate in \
  "$binary_root/codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}" \
  "$binary_root/codex" \
  "$binary_root/codex-zh-bin"
do
  if [ -f "$candidate" ]; then
    binary="$candidate"
    break
  fi
done
[ -n "$binary" ] || fail "Codex 固定归档中没有目标二进制"
[ "$(sha256_file "$binary")" = "$(printf '%s' "$CODEX_ZH_BIN_SHA256" | tr '[:upper:]' '[:lower:]')" ] ||
  fail "Codex 二进制 SHA256 不匹配"

# AAPT strips the final ".gz" suffix from packaged assets. Use ".tgz" names so
# the manifest path and compressed bytes remain unchanged inside the APK.
support_archive="codex-support-$RELEASE.tgz"
binary_archive="codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}.tgz"
tar \
  --sort=name \
  --mtime='UTC 1970-01-01' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$support_root" \
  -cf - . |
  gzip -n -9 > "$work/$support_archive"

support_sha="$(sha256_file "$work/$support_archive")"
archive_sha="$(sha256_file "$ARCHIVE")"
binary_sha="$(sha256_file "$binary")"
support_count="$(
  find "$support_root" -type f -print |
    LC_ALL=C sort |
    wc -l |
    tr -d ' '
)"

cat > "$work/manifest.properties" <<EOF
schema_version=1
release=$RELEASE
version_code=$VERSION_CODE
codex_version=$CODEX_ZH_VERSION
target=$CODEX_ZH_TARGET
runtime_epoch=$CODEX_ZH_RUNTIME_EPOCH
support_archive=$support_archive
support_sha256=$support_sha
support_file_count=$support_count
binary_archive=$binary_archive
binary_archive_sha256=$archive_sha
binary_sha256=$binary_sha
EOF
manifest_sha="$(sha256_file "$work/manifest.properties")"
printf '%s  %s\n' "$manifest_sha" "manifest.properties" > "$work/manifest.sha256"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp "$work/manifest.properties" "$OUTPUT_DIR/manifest.properties"
cp "$work/manifest.sha256" "$OUTPUT_DIR/manifest.sha256"
cp "$work/$support_archive" "$OUTPUT_DIR/$support_archive"
cp "$ARCHIVE" "$OUTPUT_DIR/$binary_archive"
chmod 644 "$OUTPUT_DIR"/*
cp "$SCRIPT_DIR/codex-apk-upgrade.sh" "$ASSET_ROOT/codex-apk-upgrade.sh"
chmod 755 "$ASSET_ROOT/codex-apk-upgrade.sh"

printf 'APK payload ready: release=%s versionCode=%s files=%s output=%s\n' \
  "$RELEASE" "$VERSION_CODE" "$support_count" "$OUTPUT_DIR"
printf 'manifest_sha256=%s\n' "$manifest_sha"
printf 'support_sha256=%s\n' "$support_sha"
printf 'binary_archive_sha256=%s\n' "$archive_sha"
printf 'binary_sha256=%s\n' "$binary_sha"
