#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="${1:-$ROOT_DIR/android-arm64-musl/install-reterminal-alpine.sh}"
BOOTSTRAP="${2:-$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F "$pattern" "$file" >/dev/null 2>&1 || {
    printf '%s\n' "--- $file ---" >&2
    sed -n '1,160p' "$file" >&2 || true
    fail "expected pattern not found: $pattern"
  }
}

make_installer_lib() {
  src="$1"
  dest="$2"
  awk '
    /^arch="/ { exit }
    { print }
  ' "$src" > "$dest"
}

make_bootstrap_lib() {
  src="$1"
  dest="$2"
  awk '
    /^if \[ "\$\{CODEX_FOR_TUI_AUTO_START:-1\}"/ { exit }
    { print }
  ' "$src" > "$dest"
}

test_print_download_plan_blank_notice_returns_zero() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-plan.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  make_installer_lib "$INSTALLER" "$tmp/installer-lib.sh"

  (
    # shellcheck disable=SC1091
    . "$tmp/installer-lib.sh"
    NOTICE_URL=""
    print_download_plan >"$tmp/stdout" 2>"$tmp/stderr"
  )

  assert_file_contains "$tmp/stderr" "Codex for TUI 环境检查"
  assert_file_contains "$tmp/stderr" "Codex 压缩包来自 GitHub raw"
  rm -rf "$tmp"
}

test_confirm_deps_choice_minimal_continues() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-deps.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/bin" "$tmp/home" "$tmp/state"
  make_installer_lib "$INSTALLER" "$tmp/installer-lib.sh"

  cat > "$tmp/bin/apk" <<'APK'
#!/usr/bin/env sh
exit 0
APK
  chmod +x "$tmp/bin/apk"
  printf '1\n' > "$tmp/input"

  (
    # shellcheck disable=SC1091
    . "$tmp/installer-lib.sh"
    export HOME="$tmp/home"
    export PATH="$tmp/bin:/bin:/usr/bin"
    export CODEX_ZH_FORCE_STDIN=1
    STATE_ROOT="$tmp/state"
    DOWNLOAD_METHOD_FILE="$STATE_ROOT/download-method"
    DEPS_CONFIRM_FILE="$STATE_ROOT/deps-confirmed"
    SKIP_DEPS=0
    DEPS_PROFILE=full
    NOTICE_URL=""
    confirm_deps_install >"$tmp/stdout" 2>"$tmp/stderr" < "$tmp/input"
  ) || {
    printf '%s\n' "--- confirm_deps_install stdout ---" >&2
    sed -n '1,160p' "$tmp/stdout" >&2 || true
    printf '%s\n' "--- confirm_deps_install stderr ---" >&2
    sed -n '1,220p' "$tmp/stderr" >&2 || true
    fail "confirm_deps_install did not complete"
  }

  assert_file_contains "$tmp/stderr" "请选择依赖安装方式"
  [ "$(sed -n '1p' "$tmp/state/deps-confirmed")" = "minimal" ] || fail "choice 1 did not persist minimal profile"
  rm -rf "$tmp"
}

test_bootstrap_continue_writes_consent() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/prefix"
  make_bootstrap_lib "$BOOTSTRAP" "$tmp/bootstrap-lib.sh"
  printf '1\n' > "$tmp/input"

  (
    # shellcheck disable=SC1091
    . "$tmp/bootstrap-lib.sh"
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    BOOT_DIR="$HOME/.codex-for-tui"
    CONSENT_FILE="$BOOT_DIR/install-consent"
    mkdir -p "$BOOT_DIR"
    confirm_first_install >"$tmp/stdout" 2>"$tmp/stderr" < "$tmp/input"
  ) || {
    printf '%s\n' "--- confirm_first_install stdout ---" >&2
    sed -n '1,160p' "$tmp/stdout" >&2 || true
    printf '%s\n' "--- confirm_first_install stderr ---" >&2
    sed -n '1,220p' "$tmp/stderr" >&2 || true
    fail "confirm_first_install did not complete"
  }

  [ -s "$tmp/home/.codex-for-tui/install-consent" ] || fail "bootstrap consent file was not written"
  assert_file_contains "$tmp/stderr" "Codex for TUI 首次安装"
  rm -rf "$tmp"
}

run_step() {
  name="$1"
  (
    sleep 10
    printf 'FAIL: timed out: %s\n' "$name" >&2
    kill "$$" 2>/dev/null || true
  ) &
  watchdog="$!"
  "$name"
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
}

sh -n "$INSTALLER"
sh -n "$BOOTSTRAP"
run_step test_print_download_plan_blank_notice_returns_zero
run_step test_confirm_deps_choice_minimal_continues
run_step test_bootstrap_continue_writes_consent
printf 'OK: Codex for TUI installer smoke tests passed\n'
