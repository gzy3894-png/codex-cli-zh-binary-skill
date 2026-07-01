#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="${1:-$ROOT_DIR/android-arm64-musl/install-reterminal-alpine.sh}"
BOOTSTRAP="${2:-$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh}"
RESUME="${3:-$ROOT_DIR/android-arm64-musl/codex-local-resume.sh}"

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

make_resume_lib() {
  src="$1"
  dest="$2"
  awk '
    /^main "\$@"/ { exit }
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
  assert_file_contains "$tmp/stderr" "Codex 压缩包来自 GitHub Release"
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

test_resume_menu_rejects_pasted_url_choice() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-menu.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/state" "$tmp/bin"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  printf 'https://api.krill-ai.com/v1\nq\n' > "$tmp/input"

  set +e
  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_FORCE_STDIN=1
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    mkdir -p "$STATE_DIR" "$CONFIGS_DIR"
    select_or_create_profile >"$tmp/stdout" 2>"$tmp/stderr" < "$tmp/input"
  )
  rc="$?"
  set -e

  [ "$rc" -eq 130 ] || {
    sed -n '1,220p' "$tmp/stderr" >&2 || true
    fail "pasted URL menu test exited with $rc, expected 130"
  }
  assert_file_contains "$tmp/stderr" "你可能把 API Base URL 粘到了菜单编号处"
  assert_file_contains "$tmp/stderr" "URL 要在选择 2 之后再填写"
  rm -rf "$tmp"
}

test_resume_rejects_invalid_api_base_before_fetch() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-url.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/state"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  printf '5\nq\n' > "$tmp/input"

  set +e
  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_FORCE_STDIN=1
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    mkdir -p "$STATE_DIR" "$CONFIGS_DIR"
    fetch_models() {
      printf '%s\n' "fetch_models should not be called for invalid URL" >&2
      return 99
    }
    create_third_party_profile >"$tmp/stdout" 2>"$tmp/stderr" < "$tmp/input"
  )
  rc="$?"
  set -e

  [ "$rc" -eq 130 ] || {
    sed -n '1,220p' "$tmp/stderr" >&2 || true
    fail "invalid API Base URL test exited with $rc, expected 130"
  }
  assert_file_contains "$tmp/stderr" "API Base URL 格式不对：5"
  if grep -F "fetch_models should not be called" "$tmp/stderr" >/dev/null 2>&1; then
    fail "invalid API Base URL reached fetch_models"
  fi
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
sh -n "$RESUME"
run_step test_print_download_plan_blank_notice_returns_zero
run_step test_confirm_deps_choice_minimal_continues
run_step test_bootstrap_continue_writes_consent
run_step test_resume_menu_rejects_pasted_url_choice
run_step test_resume_rejects_invalid_api_base_before_fetch
printf 'OK: Codex for TUI installer smoke tests passed\n'
