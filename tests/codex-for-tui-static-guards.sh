#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
MKSESSION="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MkSession.kt"
INIT_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/init.sh"
BOOTSTRAP="$SCRIPT_DIR/codex-for-tui-bootstrap.sh"
BOOTSTRAP_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "expected pattern not found in $file: $pattern"
}

assert_file_not_contains() {
  file="$1"
  pattern="$2"
  if grep -F -- "$pattern" "$file" >/dev/null 2>&1; then
    fail "unexpected pattern found in $file: $pattern"
  fi
}

run_step() {
  name="$1"
  printf 'RUN %s\n' "$name"
  "$name"
}

test_android_session_uses_root_codex_home() {
  assert_file_not_contains "$MKSESSION" 'HOME=/sdcard'
  assert_file_contains "$MKSESSION" 'HOME=/root'
  assert_file_contains "$MKSESSION" 'CODEX_HOME=/root/.codex'
  assert_file_contains "$INIT_ASSET" 'export HOME="${HOME:-/root}"'
  assert_file_contains "$INIT_ASSET" 'export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"'
}

test_bootstrap_asset_is_synced() {
  cmp "$BOOTSTRAP" "$BOOTSTRAP_ASSET" >/dev/null 2>&1 || fail "bootstrap source and APK asset differ"
}

test_generated_launcher_entrypoints_and_normal_path() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-launcher.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/bin" "$tmp/state" "$tmp/curl"
  printf 'configured = true\n' > "$tmp/home/.codex/config.toml"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
printf 'real-codex:%s:%s:%s\n' "$HOME" "$CODEX_HOME" "$*"
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  cat > "$tmp/bin/codex-update" <<'EOF'
#!/usr/bin/env sh
printf 'update-ran:%s\n' "$*"
EOF
  chmod +x "$tmp/bin/codex-update"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_write_launcher
  )

  assert_file_contains "$tmp/bin/codex" '配置模式'
  assert_file_contains "$tmp/bin/codex" '更新'
  assert_file_contains "$tmp/bin/codex" 'CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"'
  assert_file_not_contains "$tmp/bin/codex" '--preflight'
  assert_file_not_contains "$tmp/bin/codex" '--refresh-current-profile'
  assert_file_not_contains "$tmp/bin/codex" 'refresh-models'

  if ! output="$(
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" hello
  )"; then
    fail "normal codex launcher command failed"
  fi
  printf '%s\n' "$output" | grep -F 'real-codex:' >/dev/null 2>&1 || fail "normal codex did not run real binary"
  printf '%s\n' "$output" | grep -F 'update-ran' >/dev/null 2>&1 && fail "normal codex invoked update path"
  printf '%s\n' "$output" | grep -F ':/root:' >/dev/null 2>&1 && fail "test did not isolate HOME"

  if ! output="$(
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" 更新
  )"; then
    fail "codex update launcher command failed"
  fi
  printf '%s\n' "$output" | grep -F 'update-ran:apply' >/dev/null 2>&1 || fail "codex 更新 did not invoke codex-update apply"
  rm -rf "$tmp"
}

test_generated_launcher_first_run_configures_then_runs() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-first-run.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/bin"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
printf 'real-codex-after-config:%s\n' "$*"
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  cat > "$tmp/home/.local/bin/curl" <<'EOF'
#!/usr/bin/env sh
dest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      dest="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$dest" ] || exit 9
mkdir -p "$(dirname "$dest")"
printf '{"data":[{"id":"codex-test-model"}]}\n' > "$dest"
EOF
  chmod +x "$tmp/home/.local/bin/curl"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_write_launcher
  )

  if ! output="$(
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    CODEX_ZH_SETUP_MODE=third_party \
    CODEX_ZH_API_BASE=https://api.example.test/v1 \
    CODEX_ZH_API_KEY=sk-test \
    CODEX_ZH_DEFAULT_MODEL=codex-test-model \
    CODEX_ZH_FORCE_STDIN=1 \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" 2>"$tmp/stderr"
  )"; then
    [ ! -s "$tmp/stderr" ] || sed -n '1,80p' "$tmp/stderr" >&2 || true
    fail "first run launcher command failed"
  fi

  [ -s "$tmp/home/.codex/config.toml" ] || fail "first run did not write config.toml"
  assert_file_contains "$tmp/home/.codex/config.toml" 'model = "codex-test-model"'
  printf '%s\n' "$output" | grep -F 'real-codex-after-config:' >/dev/null 2>&1 || fail "first run did not continue into real codex"

  rm -rf "$tmp"
}

run_step test_android_session_uses_root_codex_home
run_step test_bootstrap_asset_is_synced
run_step test_generated_launcher_entrypoints_and_normal_path
run_step test_generated_launcher_first_run_configures_then_runs
printf 'OK: Codex for TUI static guards passed\n'
