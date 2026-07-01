#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="${1:-$ROOT_DIR/android-arm64-musl/install-reterminal-alpine.sh}"
BOOTSTRAP="${2:-$ROOT_DIR/android-arm64-musl/codex-for-tui-bootstrap.sh}"
BOOTSTRAP_ASSET="${3:-$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh}"
RESUME="${4:-$ROOT_DIR/android-arm64-musl/codex-local-resume.sh}"

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

assert_file_not_contains() {
  file="$1"
  pattern="$2"
  if grep -F "$pattern" "$file" >/dev/null 2>&1; then
    printf '%s\n' "--- $file ---" >&2
    sed -n '1,160p' "$file" >&2 || true
    fail "unexpected pattern found: $pattern"
  fi
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

test_bootstrap_script_url_candidates_include_raw_then_release() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-urls.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  make_bootstrap_lib "$BOOTSTRAP" "$tmp/bootstrap-lib.sh"

  (
    # shellcheck disable=SC1091
    . "$tmp/bootstrap-lib.sh"
    SCRIPT_BASE_URL="https://raw.example.test/repo/branch/android-arm64-musl"
    SCRIPT_RELEASE_BASE_URL="https://github.example.test/repo/releases/latest/download"
    script_url_candidates "install-reterminal-alpine.sh" ""
  ) > "$tmp/urls"

  [ "$(sed -n '1p' "$tmp/urls")" = "https://raw.example.test/repo/branch/android-arm64-musl/install-reterminal-alpine.sh" ] || fail "raw script URL candidate was not first"
  [ "$(sed -n '2p' "$tmp/urls")" = "https://github.example.test/repo/releases/latest/download/install-reterminal-alpine.sh" ] || fail "release script URL candidate was not second"
  rm -rf "$tmp"
}

test_bootstrap_refresh_remote_script_keeps_cache_on_failure() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-cache.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/bin" "$tmp/home"
  make_bootstrap_lib "$BOOTSTRAP" "$tmp/bootstrap-lib.sh"
  printf '%s\n' "cached-script" > "$tmp/cached.sh"

  cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env sh
exit 22
EOF
  chmod +x "$tmp/bin/curl"

  (
    # shellcheck disable=SC1091
    . "$tmp/bootstrap-lib.sh"
    export HOME="$tmp/home"
    export PATH="$tmp/bin:/bin:/usr/bin"
    SCRIPT_BASE_URL="https://raw.example.test/repo/branch/android-arm64-musl"
    SCRIPT_RELEASE_BASE_URL="https://github.example.test/repo/releases/latest/download"
    refresh_remote_script "安装脚本" "install-reterminal-alpine.sh" "" "$tmp/cached.sh"
  ) >"$tmp/stdout" 2>"$tmp/stderr" || fail "refresh_remote_script should have reused cache"

  [ "$(sed -n '1p' "$tmp/cached.sh")" = "cached-script" ] || fail "cached script changed after failed refresh"
  assert_file_contains "$tmp/stderr" "继续使用本地缓存"
  rm -rf "$tmp"
}

test_bootstrap_resume_requires_existing_state() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-resume-state.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"
  make_bootstrap_lib "$BOOTSTRAP" "$tmp/bootstrap-lib.sh"

  (
    # shellcheck disable=SC1091
    . "$tmp/bootstrap-lib.sh"
    export HOME="$tmp/home"
    unset CODEX_HOME
    has_resume_state
  ) && fail "has_resume_state should be false without any state"

  mkdir -p "$tmp/home/.codex/install-state"
  (
    # shellcheck disable=SC1091
    . "$tmp/bootstrap-lib.sh"
    export HOME="$tmp/home"
    unset CODEX_HOME
    has_resume_state
  ) || fail "has_resume_state should be true when install-state exists"

  rm -rf "$tmp"
}

test_bootstrap_refreshes_remote_scripts_before_launching_codex() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-refresh-before-codex.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/prefix"

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
      last="$1"
      shift
      ;;
  esac
done
[ -n "$dest" ] || exit 9
printf '#!/usr/bin/env sh\nexit 0\n' > "$dest"
EOF
  chmod +x "$tmp/home/.local/bin/curl"

  cat > "$tmp/home/.local/bin/codex" <<'EOF'
#!/usr/bin/env sh
[ -s "$HOME/.codex-for-tui/remote/install-reterminal-alpine.sh" ] || exit 11
[ -s "$HOME/.codex-for-tui/remote/codex-local-resume.sh" ] || exit 12
printf 'codex-ran\n'
EOF
  chmod +x "$tmp/home/.local/bin/codex"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export PATH="/bin:/usr/bin"
    export CODEX_ZH_SCRIPT_BASE_URL="https://raw.example.test/repo/branch/android-arm64-musl"
    export CODEX_ZH_SCRIPT_RELEASE_BASE_URL="https://github.example.test/repo/releases/latest/download"
    sh "$BOOTSTRAP" >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,220p' "$tmp/stderr" >&2 || true
    fail "bootstrap did not refresh remote scripts before launching codex"
  }

  assert_file_contains "$tmp/stdout" "codex-ran"
  [ -s "$tmp/home/.codex-for-tui/remote/install-reterminal-alpine.sh" ] || fail "installer was not refreshed before codex launch"
  [ -s "$tmp/home/.codex-for-tui/remote/codex-local-resume.sh" ] || fail "resume script was not refreshed before codex launch"
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

test_installer_config_uses_provider_auth_and_model_catalog() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-installer-config.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"
  make_installer_lib "$INSTALLER" "$tmp/installer-lib.sh"
  cat > "$tmp/models.txt" <<'EOF'
gpt-test
deepseek-v4-flash:free
EOF

  (
    # shellcheck disable=SC1091
    . "$tmp/installer-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    PROVIDER_ID="custom"
    write_codex_config "https://api.example.com/v1" "sk-test-token" "gpt-test" "$tmp/models.txt"
  )

  config="$tmp/home/.codex/config.toml"
  helper="$tmp/home/.codex/bin/provider-api-key"
  catalog="$tmp/home/.codex/model-catalog.json"
  assert_file_contains "$config" 'requires_openai_auth = false'
  assert_file_contains "$config" '[model_providers.custom.auth]'
  assert_file_contains "$config" "command = \"$helper\""
  assert_file_contains "$config" "model_catalog_json = \"$catalog\""
  assert_file_contains "$config" 'auto_compaction = true'
  assert_file_contains "$config" '"gpt-5.3-codex" = "gpt-5.4"'
  [ -e "$catalog" ] || fail "installer did not create model-catalog.json"
  assert_file_contains "$catalog" '"slug": "gpt-test"'
  assert_file_contains "$catalog" '"slug": "deepseek-v4-flash:free"'
  [ "$("$helper")" = "sk-test-token" ] || fail "provider auth helper did not read auth.json"
  rm -rf "$tmp"
}

test_resume_migrates_legacy_model_catalog_profile() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-migrate.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/profile"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  cat > "$tmp/profile/config.toml" <<'EOF'
model_provider = "custom"
model = "gpt-legacy"
model_catalog_json = "/root/.codex/model-catalog.json"

[model_providers.custom]
name = "custom"
base_url = "https://api.example.com/v1"
wire_api = "responses"
requires_openai_auth = true
EOF
  printf '%s\n' "third_party" > "$tmp/profile/setup-mode"
  printf '%s\n' "https://api.example.com/v1" > "$tmp/profile/api-base"
  printf '%s\n' "gpt-legacy" > "$tmp/profile/default-model"
  printf '%s\n' "gpt-legacy" > "$tmp/profile/enabled-models.txt"
  printf '%s\n' '{"OPENAI_API_KEY":"sk-legacy-token"}' > "$tmp/profile/auth.json"
  printf '%s\n' '{"models":[]}' > "$tmp/profile/model-catalog.json"

  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    PROVIDER_ID="custom"
    migrate_third_party_profile_if_needed "$tmp/profile"
  )

  config="$tmp/profile/config.toml"
  helper="$tmp/profile/bin/provider-api-key"
  catalog="$tmp/profile/model-catalog.json"
  assert_file_contains "$config" 'requires_openai_auth = false'
  assert_file_contains "$config" '[model_providers.custom.auth]'
  assert_file_contains "$config" "command = \"$helper\""
  assert_file_contains "$config" "model_catalog_json = \"$catalog\""
  [ -e "$catalog" ] || fail "legacy model-catalog.json was not recreated"
  assert_file_contains "$catalog" '"slug": "gpt-legacy"'
  [ "$("$helper")" = "sk-legacy-token" ] || fail "migrated provider auth helper did not read auth.json"
  rm -rf "$tmp"
}

test_resume_edit_third_party_profile_updates_provider_config() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-edit-profile.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/api-profiles/krill" "$tmp/home/.codex/install-state"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  printf 'Krill Old\n' > "$tmp/home/.codex/api-profiles/krill/name"
  printf 'third_party\n' > "$tmp/home/.codex/api-profiles/krill/setup-mode"
  printf 'https://api.old.example.com/v1\n' > "$tmp/home/.codex/api-profiles/krill/api-base"
  printf 'gpt-old\n' > "$tmp/home/.codex/api-profiles/krill/default-model"
  printf 'gpt-old\n' > "$tmp/home/.codex/api-profiles/krill/models.txt"
  printf 'gpt-old\n' > "$tmp/home/.codex/api-profiles/krill/enabled-models.txt"
  printf '%s\n' '{"OPENAI_API_KEY":"sk-old-token"}' > "$tmp/home/.codex/api-profiles/krill/auth.json"
  printf 'Krill New\nhttps://api.new.example.com/v1\n\n' > "$tmp/input"

  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_FORCE_STDIN=1
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    fetch_models_or_prompt() {
      printf '%s\n' "gpt-new" > "$3"
      printf '%s\n' "deepseek-v4-flash:free" >> "$3"
      return 0
    }
    select_enabled_models_text() { cat "$1"; }
    choose_model() { sed -n '2p' "$1"; }
    edit_third_party_profile "$CONFIGS_DIR/krill" >"$tmp/stdout" 2>"$tmp/stderr" < "$tmp/input"
  ) || {
    sed -n '1,240p' "$tmp/stderr" >&2 || true
    fail "edit_third_party_profile did not complete"
  }

  profile_dir="$tmp/home/.codex/api-profiles/krill"
  config="$profile_dir/config.toml"
  helper="$profile_dir/bin/provider-api-key"
  catalog="$profile_dir/model-catalog.json"
  [ "$(sed -n '1p' "$profile_dir/name")" = "Krill New" ] || fail "profile name was not updated"
  [ "$(sed -n '1p' "$profile_dir/api-base")" = "https://api.new.example.com/v1" ] || fail "profile API base was not updated"
  [ "$(sed -n '1p' "$profile_dir/default-model")" = "deepseek-v4-flash:free" ] || fail "profile default model was not updated"
  assert_file_contains "$config" 'base_url = "https://api.new.example.com/v1"'
  assert_file_contains "$config" 'model = "deepseek-v4-flash:free"'
  assert_file_contains "$catalog" '"slug": "gpt-new"'
  assert_file_contains "$catalog" '"slug": "deepseek-v4-flash:free"'
  [ "$("$helper")" = "sk-old-token" ] || fail "edited profile did not preserve existing API key when left blank"
  rm -rf "$tmp"
}

test_resume_delete_profile_clears_active_copy() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-delete-profile.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/api-profiles/krill" "$tmp/home/.codex/install-state" "$tmp/home/.codex/bin"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  printf 'Krill\n' > "$tmp/home/.codex/api-profiles/krill/name"
  printf 'third_party\n' > "$tmp/home/.codex/api-profiles/krill/setup-mode"
  printf 'krill\n' > "$tmp/home/.codex/api-profiles/last-profile"
  printf 'active\n' > "$tmp/home/.codex/install-state/active-profile-label"
  printf 'cfg\n' > "$tmp/home/.codex/config.toml"
  printf 'auth\n' > "$tmp/home/.codex/auth.json"
  printf 'catalog\n' > "$tmp/home/.codex/model-catalog.json"
  printf '#!/usr/bin/env sh\n' > "$tmp/home/.codex/bin/provider-api-key"
  chmod +x "$tmp/home/.codex/bin/provider-api-key"
  printf 'y\n' > "$tmp/input"

  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_FORCE_STDIN=1
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    delete_profile "$CONFIGS_DIR/krill" >"$tmp/stdout" 2>"$tmp/stderr" < "$tmp/input"
  ) || fail "delete_profile did not complete"

  [ ! -d "$tmp/home/.codex/api-profiles/krill" ] || fail "profile directory was not deleted"
  [ ! -e "$tmp/home/.codex/api-profiles/last-profile" ] || fail "last-profile marker was not cleared"
  [ ! -e "$tmp/home/.codex/config.toml" ] || fail "active config copy was not cleared"
  [ ! -e "$tmp/home/.codex/auth.json" ] || fail "active auth copy was not cleared"
  [ ! -e "$tmp/home/.codex/model-catalog.json" ] || fail "active model catalog copy was not cleared"
  [ ! -e "$tmp/home/.codex/bin/provider-api-key" ] || fail "active provider helper was not cleared"
  rm -rf "$tmp"
}

test_resume_status_accepts_model_catalog_config() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-status-model-catalog.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/install-state" "$tmp/home/.codex/api-profiles" "$tmp/bin"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  for file in "$tmp/bin/codex-zh-bin" "$tmp/bin/.codex-launcher-real" "$tmp/bin/codex"; do
    printf '#!/usr/bin/env sh\nexit 0\n' > "$file"
    chmod +x "$file"
  done
  printf 'agents\n' > "$tmp/home/.codex/AGENTS.md"
  printf 'cfg\nmodel_catalog_json = "/root/.codex/model-catalog.json"\n' > "$tmp/home/.codex/config.toml"
  printf '{"OPENAI_API_KEY":"sk"}\n' > "$tmp/home/.codex/auth.json"

  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    INSTALL_DIR="$tmp/bin"
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    REAL_BIN="$INSTALL_DIR/codex-zh-bin"
    WRAPPER="$INSTALL_DIR/.codex-launcher-real"
    LAUNCHER="$INSTALL_DIR/codex"
    check_status >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stdout" >&2 || true
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "check_status should accept configs that use model_catalog_json"
  }

  assert_file_not_contains "$tmp/stdout" "legacy_model_catalog_config"
  rm -rf "$tmp"
}

test_resume_refresh_current_profile_updates_current_third_party_profile() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-refresh-current-profile.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/api-profiles/krill" "$tmp/home/.codex/install-state" "$tmp/home/.codex/bin"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  profile_dir="$tmp/home/.codex/api-profiles/krill"
  printf 'Krill\n' > "$profile_dir/name"
  printf 'third_party\n' > "$profile_dir/setup-mode"
  printf 'https://api.krill.example.com/v1\n' > "$profile_dir/api-base"
  printf 'deepseek-old\n' > "$profile_dir/default-model"
  printf 'deepseek-old\nlegacy-only\n' > "$profile_dir/models.txt"
  printf 'deepseek-old\nlegacy-only\n' > "$profile_dir/enabled-models.txt"
  printf '%s\n' '{"OPENAI_API_KEY":"sk-krill-old"}' > "$profile_dir/auth.json"
  printf 'krill\n' > "$tmp/home/.codex/api-profiles/last-profile"

  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    fetch_models_or_prompt() {
      printf '%s\n' "deepseek-old" > "$3"
      printf '%s\n' "gpt-5.5" >> "$3"
      printf '%s\n' "new-only" >> "$3"
      return 0
    }
    refresh_current_profile >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "refresh_current_profile did not complete"
  }

  assert_file_contains "$profile_dir/enabled-models.txt" "deepseek-old"
  assert_file_not_contains "$profile_dir/enabled-models.txt" "legacy-only"
  [ "$(sed -n '1p' "$profile_dir/default-model")" = "deepseek-old" ] || fail "default model should be preserved when still available"
  assert_file_contains "$profile_dir/model-catalog.json" '"slug": "gpt-5.5"'
  assert_file_contains "$profile_dir/config.toml" 'model = "deepseek-old"'
  [ "$("$profile_dir/bin/provider-api-key")" = "sk-krill-old" ] || fail "refresh should preserve existing API key"
  assert_file_contains "$tmp/home/.codex/config.toml" 'model = "deepseek-old"'
  assert_file_contains "$tmp/home/.codex/model-catalog.json" '"slug": "new-only"'
  rm -rf "$tmp"
}

test_resume_refresh_current_profile_noops_for_official_profile() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-resume-refresh-official.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/api-profiles/official" "$tmp/home/.codex/install-state"
  make_resume_lib "$RESUME" "$tmp/resume-lib.sh"
  printf '官方登录入口\n' > "$tmp/home/.codex/api-profiles/official/name"
  printf 'official\n' > "$tmp/home/.codex/api-profiles/official/setup-mode"
  printf 'official\n' > "$tmp/home/.codex/api-profiles/last-profile"

  (
    # shellcheck disable=SC1091
    . "$tmp/resume-lib.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    STATE_DIR="$CODEX_HOME/install-state"
    CONFIGS_DIR="$CODEX_HOME/api-profiles"
    LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
    refresh_current_profile >"$tmp/stdout" 2>"$tmp/stderr"
  ) || fail "refresh_current_profile should no-op for official profile"

  assert_file_contains "$tmp/stdout" "当前配置是官方登录入口"
  [ ! -e "$tmp/home/.codex/model-catalog.json" ] || fail "official refresh should not generate third-party model catalog"
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
sh -n "$BOOTSTRAP_ASSET"
sh -n "$RESUME"
cmp "$BOOTSTRAP" "$BOOTSTRAP_ASSET"
run_step test_print_download_plan_blank_notice_returns_zero
run_step test_confirm_deps_choice_minimal_continues
run_step test_bootstrap_continue_writes_consent
run_step test_bootstrap_script_url_candidates_include_raw_then_release
run_step test_bootstrap_refresh_remote_script_keeps_cache_on_failure
run_step test_bootstrap_resume_requires_existing_state
run_step test_bootstrap_refreshes_remote_scripts_before_launching_codex
run_step test_resume_menu_rejects_pasted_url_choice
run_step test_resume_rejects_invalid_api_base_before_fetch
run_step test_installer_config_uses_provider_auth_and_model_catalog
run_step test_resume_migrates_legacy_model_catalog_profile
run_step test_resume_edit_third_party_profile_updates_provider_config
run_step test_resume_delete_profile_clears_active_copy
run_step test_resume_status_accepts_model_catalog_config
run_step test_resume_refresh_current_profile_updates_current_third_party_profile
run_step test_resume_refresh_current_profile_noops_for_official_profile
printf 'OK: Codex for TUI installer smoke tests passed\n'
