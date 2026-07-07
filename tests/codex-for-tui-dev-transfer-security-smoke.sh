#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TRANSFER_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-dev-transfer"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || {
    [ ! -r "$file" ] || sed -n '1,120p' "$file" >&2 || true
    fail "expected pattern not found in $file: $pattern"
  }
}

rejects_verify() {
  file="$1"
  label="$2"
  if codex-dev-transfer verify "$file" >/dev/null 2>&1; then
    fail "verify should reject $label"
  fi
}

sh -n "$TRANSFER_ASSET" || fail "codex-dev-transfer shell syntax failed"

tmp="${TMPDIR:-/tmp}/codex-tui-dev-transfer-security-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/src-home/.codex" "$tmp/src-home/.local/share/codex-zh" \
  "$tmp/src-prefix" "$tmp/snapshots" "$tmp/target-home/.codex" "$tmp/target-prefix"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cp "$TRANSFER_ASSET" "$tmp/bin/codex-dev-transfer"
chmod 755 "$tmp/bin/codex-dev-transfer"

export PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}"
export CODEX_DEV_TRANSFER_DIR="$tmp/snapshots"
export CODEX_DEV_TRANSFER_INCLUDE_SYSTEM=0
export PKG="com.gzy3894.codexfortui"

export HOME="$tmp/src-home"
export CODEX_HOME="$tmp/src-home/.codex"
export PREFIX="$tmp/src-prefix"
cat > "$tmp/src-home/.codex/config.toml" <<'EOF'
model_provider = "custom"
EOF
printf 'share fixture\n' > "$tmp/src-home/.local/share/codex-zh/readme.txt"
snapshot_output="$(codex-dev-transfer export txn 2>&1)" || fail "fixture export failed: $snapshot_output"
snapshot="$(ls -t "$tmp/snapshots"/codex-dev-transfer-txn-*.tar.gz 2>/dev/null | sed -n '1p')"
[ -s "$snapshot" ] || fail "fixture snapshot not created"

# 导入提交阶段失败时，应回滚已替换的目标，不留下半导入状态。
export HOME="$tmp/target-home"
export CODEX_HOME="$tmp/target-home/.codex"
export PREFIX="$tmp/target-prefix"
printf 'original config\n' > "$tmp/target-home/.codex/config.toml"
printf 'not a directory\n' > "$tmp/target-home/.local"
if codex-dev-transfer import --yes --no-backup "$snapshot" >/dev/null 2>&1; then
  fail "import should fail when a target parent is a file"
fi
assert_file_contains "$tmp/target-home/.codex/config.toml" "original config"
assert_file_contains "$tmp/target-home/.local" "not a directory"

# 非白名单成员。
mkdir -p "$tmp/bad-unknown/payload/root/.codex"
printf 'format=codex-dev-transfer-v1\ninclude_secrets=0\n' > "$tmp/bad-unknown/manifest.txt"
printf 'bad\n' > "$tmp/bad-unknown/evil.txt"
(cd "$tmp/bad-unknown" && tar -czf "$tmp/bad-unknown.tar.gz" manifest.txt evil.txt)
rejects_verify "$tmp/bad-unknown.tar.gz" "unknown member"

# symlink 成员。
mkdir -p "$tmp/bad-link/payload/root/.codex"
printf 'format=codex-dev-transfer-v1\ninclude_secrets=0\n' > "$tmp/bad-link/manifest.txt"
ln -s /etc/passwd "$tmp/bad-link/payload/root/.codex/link-out"
if (cd "$tmp/bad-link" && tar -czf "$tmp/bad-link.tar.gz" manifest.txt payload) 2>/dev/null &&
  tar -tvzf "$tmp/bad-link.tar.gz" 2>/dev/null | grep -E '(^l| -> )' >/dev/null 2>&1; then
  rejects_verify "$tmp/bad-link.tar.gz" "symlink member"
fi

# hardlink 成员；部分 BusyBox tar 会退化为普通文件，只有确认为 hardlink 时断言拒绝。
mkdir -p "$tmp/bad-hard/payload/root/.codex"
printf 'format=codex-dev-transfer-v1\ninclude_secrets=0\n' > "$tmp/bad-hard/manifest.txt"
printf 'hard\n' > "$tmp/bad-hard/payload/root/.codex/a"
if ln "$tmp/bad-hard/payload/root/.codex/a" "$tmp/bad-hard/payload/root/.codex/b" 2>/dev/null; then
  if (cd "$tmp/bad-hard" && tar -czf "$tmp/bad-hard.tar.gz" manifest.txt payload) 2>/dev/null &&
    tar -tvzf "$tmp/bad-hard.tar.gz" 2>/dev/null | grep -E '(^h| link to | -> )' >/dev/null 2>&1; then
    rejects_verify "$tmp/bad-hard.tar.gz" "hardlink member"
  fi
fi

# device 成员（环境允许 mknod 时才测试）。
if command -v mknod >/dev/null 2>&1; then
  mkdir -p "$tmp/bad-device/payload/root/.codex"
  printf 'format=codex-dev-transfer-v1\ninclude_secrets=0\n' > "$tmp/bad-device/manifest.txt"
  if mknod "$tmp/bad-device/payload/root/.codex/null-device" c 1 3 2>/dev/null; then
    (cd "$tmp/bad-device" && tar -czf "$tmp/bad-device.tar.gz" manifest.txt payload)
    if tar -tvzf "$tmp/bad-device.tar.gz" 2>/dev/null | grep -E '^[bc]' >/dev/null 2>&1; then
      rejects_verify "$tmp/bad-device.tar.gz" "device member"
    fi
  fi
fi

# GNU tar 可构造 .. 和绝对路径成员时，验证路径穿越保护。
if tar --help 2>&1 | grep -- '--transform' >/dev/null 2>&1; then
  mkdir -p "$tmp/bad-dotdot"
  printf 'format=codex-dev-transfer-v1\ninclude_secrets=0\n' > "$tmp/bad-dotdot/manifest.txt"
  printf 'dotdot\n' > "$tmp/bad-dotdot/safe.txt"
  (cd "$tmp/bad-dotdot" && tar -czf "$tmp/bad-dotdot.tar.gz" --transform 's#safe.txt#payload/root/.codex/../../evil.txt#' manifest.txt safe.txt)
  rejects_verify "$tmp/bad-dotdot.tar.gz" ".. member"
fi

abs_src="$tmp/abs-member.txt"
printf 'absolute\n' > "$abs_src"
if tar -czPf "$tmp/bad-absolute.tar.gz" "$abs_src" >/dev/null 2>&1; then
  rejects_verify "$tmp/bad-absolute.tar.gz" "absolute member"
fi

printf 'OK: Codex for TUI dev transfer security smoke passed\n'
