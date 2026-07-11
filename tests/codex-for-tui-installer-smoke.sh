#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
BOOTSTRAP="$SCRIPT_DIR/codex-for-tui-bootstrap.sh"
BOOTSTRAP_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh"
RESUME="$SCRIPT_DIR/codex-local-resume.sh"
UPDATE="$SCRIPT_DIR/codex-update.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || {
    printf '%s\n' "--- $file ---" >&2
    sed -n '1,180p' "$file" >&2 || true
    fail "expected pattern not found: $pattern"
  }
}

assert_file_not_contains() {
  file="$1"
  pattern="$2"
  if grep -F -- "$pattern" "$file" >/dev/null 2>&1; then
    printf '%s\n' "--- $file ---" >&2
    sed -n '1,180p' "$file" >&2 || true
    fail "unexpected pattern found: $pattern"
  fi
}

run_step() {
  name="$1"
  printf 'RUN %s\n' "$name"
  "$name"
}

test_syntax_and_asset_sync() {
  for file in \
    "$SCRIPT_DIR/codex-for-tui-bootstrap.sh" \
    "$SCRIPT_DIR/codex-for-tui-self-test.sh" \
    "$SCRIPT_DIR/codex-local-resume.sh" \
    "$SCRIPT_DIR/codex-update.sh" \
    "$SCRIPT_DIR/install-reterminal-alpine.sh" \
    "$SCRIPT_DIR/install-alpine-proot.sh" \
    "$SCRIPT_DIR/install.sh" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/init.sh" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/init-host.sh" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-preview" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-push-image" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-push-media" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-browser" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-doctor" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-clean" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-ops" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-ops-lib" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-dev-transfer" \
    "$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh" \
    "$SCRIPT_DIR/lib/codex-zh-common.sh" \
    "$SCRIPT_DIR/lib/codex-zh-download.sh" \
    "$SCRIPT_DIR/lib/codex-zh-config.sh" \
    "$SCRIPT_DIR/lib/codex-zh-local.sh" \
    "$SCRIPT_DIR/lib/codex-zh-update.sh"
  do
    sh -n "$file"
  done
  cmp "$BOOTSTRAP" "$BOOTSTRAP_ASSET"
}

test_dev_transfer_smoke() {
  sh "$ROOT_DIR/tests/codex-for-tui-dev-transfer-smoke.sh"
}

test_config_v2_smoke() {
  sh "$ROOT_DIR/tests/codex-for-tui-config-v2-smoke.sh"
  sh "$ROOT_DIR/tests/codex-for-tui-config-v2-ui-smoke.sh"
}

test_bootstrap_normal_start_does_not_fetch_when_codex_exists() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-no-fetch.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/prefix"

  cat > "$tmp/home/.local/bin/codex" <<'EOF'
#!/usr/bin/env sh
printf 'codex-ran\n'
EOF
  chmod +x "$tmp/home/.local/bin/codex"

  cat > "$tmp/home/.local/bin/curl" <<'EOF'
#!/usr/bin/env sh
printf 'curl-called\n' >> "$HOME/network.log"
exit 99
EOF
  chmod +x "$tmp/home/.local/bin/curl"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    # 2.4.5+: default is shell-first; do not auto-exec codex.
    sh "$BOOTSTRAP" >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,160p' "$tmp/stderr" >&2 || true
    fail "bootstrap normal start should return to shell without network"
  }

  assert_file_contains "$tmp/stdout" "环境就绪"
  assert_file_not_contains "$tmp/stdout" "codex-ran"
  [ ! -e "$tmp/home/network.log" ] || fail "normal startup called network fetch"
  [ ! -e "$tmp/home/.codex-for-tui/remote/install-reterminal-alpine.sh" ] || fail "normal startup refreshed scripts"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    export CODEX_FOR_TUI_AUTO_START=1
    sh "$BOOTSTRAP" >"$tmp/stdout-auto" 2>"$tmp/stderr-auto"
  ) || {
    sed -n '1,160p' "$tmp/stderr-auto" >&2 || true
    fail "bootstrap AUTO_START=1 should launch local codex"
  }
  assert_file_contains "$tmp/stdout-auto" "codex-ran"
  rm -rf "$tmp"
}

test_bootstrap_explicit_update_fetches_scripts() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-update.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/prefix"

  cat > "$tmp/home/.local/bin/curl" <<'EOF'
#!/usr/bin/env sh
dest=""
last=""
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
mkdir -p "$(dirname "$dest")"
printf '#!/usr/bin/env sh\n# fetched %s\n' "$last" > "$dest"
EOF
  chmod +x "$tmp/home/.local/bin/curl"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    export CODEX_ZH_SCRIPT_BASE_URL="https://raw.example.test/repo/android-arm64-musl"
    export CODEX_ZH_SCRIPT_RELEASE_BASE_URL=""
    sh "$BOOTSTRAP" --update-scripts >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "explicit bootstrap update should fetch scripts"
  }

  [ -s "$tmp/home/.codex-for-tui/remote/install-reterminal-alpine.sh" ] || fail "installer was not fetched"
  [ -s "$tmp/home/.codex-for-tui/remote/codex-update.sh" ] || fail "update command was not fetched"
  [ -s "$tmp/home/.codex-for-tui/remote/codex-for-tui-self-test.sh" ] || fail "self-test script was not fetched"
  [ -s "$tmp/home/.codex-for-tui/remote/lib/codex-zh-common.sh" ] || fail "lib was not fetched"
  [ -x "$tmp/home/.local/bin/codex-update" ] || fail "codex-update command was not installed"
  [ -x "$tmp/home/.local/bin/codex-self-test" ] || fail "codex-self-test command was not installed"
  [ -x "$tmp/home/.local/bin/codex-test" ] || fail "codex-test command was not installed"
  assert_file_contains "$tmp/stdout" "已更新：install-reterminal-alpine.sh"
  rm -rf "$tmp"
}

write_fake_apk_command() {
  target="$1"
  cat > "$target" <<'EOF'
#!/usr/bin/env sh
count_file="$HOME/apk-attempts"
count=0
[ ! -s "$count_file" ] || count="$(sed -n '1p' "$count_file")"
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
printf '%s\n' "$*" >> "$HOME/apk-args"
fail_before="${CODEX_TEST_APK_FAILS_BEFORE_SUCCESS:-0}"
if [ "$count" -le "$fail_before" ]; then
  exit 42
fi
python_command="${CODEX_FOR_TUI_PYTHON3_COMMAND:-python3}"
target="$HOME/.local/bin/$python_command"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$target"
chmod 755 "$target"
EOF
  chmod 755 "$target"
}

test_bootstrap_prepares_python_dependency_with_retry() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-deps-success.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/prefix"
  write_fake_apk_command "$tmp/home/.local/bin/apk-test"
  printf '%s\n' 1 > "$tmp/input"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_PYTHON3_COMMAND=python3-test
    export CODEX_FOR_TUI_CODEX_COMMAND=codex-bootstrap-missing-test-command
    export CODEX_FOR_TUI_APK_COMMAND="$tmp/home/.local/bin/apk-test"
    export CODEX_FOR_TUI_DEPS_RETRY_DELAY_SECONDS=0
    export CODEX_TEST_APK_FAILS_BEFORE_SUCCESS=1
    sh "$BOOTSTRAP" --prepare-apk-upgrade-deps \
      < "$tmp/input" > "$tmp/stdout" 2> "$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "bootstrap dependency preparation should recover after one retry"
  }

  assert_file_contains "$tmp/home/apk-attempts" "2"
  assert_file_contains "$tmp/home/apk-args" "add --no-cache python3"
  [ -x "$tmp/home/.local/bin/python3-test" ] ||
    fail "bootstrap dependency preparation did not expose python3"
  [ -s "$tmp/home/.codex-for-tui/install-consent" ] ||
    fail "bootstrap dependency preparation did not preserve first-install consent"
  assert_file_contains "$tmp/stdout" "第 2/3 次"
  rm -rf "$tmp"
}

test_bootstrap_dependency_failure_retries_on_next_start() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-deps-retry.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/prefix"
  write_fake_apk_command "$tmp/home/.local/bin/apk-test"
  printf '%s\n' 1 > "$tmp/input"

  set +e
  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_PYTHON3_COMMAND=python3-test
    export CODEX_FOR_TUI_CODEX_COMMAND=codex-bootstrap-missing-test-command
    export CODEX_FOR_TUI_APK_COMMAND="$tmp/home/.local/bin/apk-test"
    export CODEX_FOR_TUI_DEPS_RETRY_DELAY_SECONDS=0
    export CODEX_TEST_APK_FAILS_BEFORE_SUCCESS=99
    sh "$BOOTSTRAP" --prepare-apk-upgrade-deps \
      < "$tmp/input" > "$tmp/first.stdout" 2> "$tmp/first.stderr"
  )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "bootstrap dependency preparation unexpectedly ignored repeated failure"
  assert_file_contains "$tmp/home/apk-attempts" "3"
  assert_file_contains "$tmp/first.stderr" "下次打开 App 会自动重试"
  [ ! -e "$tmp/home/.local/bin/python3-test" ] ||
    fail "failed dependency preparation left a fake python3"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_PYTHON3_COMMAND=python3-test
    export CODEX_FOR_TUI_CODEX_COMMAND=codex-bootstrap-missing-test-command
    export CODEX_FOR_TUI_APK_COMMAND="$tmp/home/.local/bin/apk-test"
    export CODEX_FOR_TUI_DEPS_RETRY_DELAY_SECONDS=0
    export CODEX_TEST_APK_FAILS_BEFORE_SUCCESS=0
    sh "$BOOTSTRAP" --prepare-apk-upgrade-deps \
      </dev/null > "$tmp/second.stdout" 2> "$tmp/second.stderr"
  ) || {
    sed -n '1,200p' "$tmp/second.stderr" >&2 || true
    fail "bootstrap dependency preparation did not retry on next start"
  }
  assert_file_contains "$tmp/home/apk-attempts" "4"
  [ -x "$tmp/home/.local/bin/python3-test" ] ||
    fail "next-start dependency retry did not install python3"
  rm -rf "$tmp"
}

test_bootstrap_dependency_cancel_does_not_install() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-bootstrap-deps-cancel.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/prefix"
  write_fake_apk_command "$tmp/home/.local/bin/apk-test"
  printf '%s\n' 2 > "$tmp/input"

  (
    export HOME="$tmp/home"
    export PREFIX="$tmp/prefix"
    export CODEX_HOME="$tmp/home/.codex"
    export PATH="/bin:/usr/bin"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_PYTHON3_COMMAND=python3-test
    export CODEX_FOR_TUI_CODEX_COMMAND=codex-bootstrap-missing-test-command
    export CODEX_FOR_TUI_APK_COMMAND="$tmp/home/.local/bin/apk-test"
    sh "$BOOTSTRAP" --prepare-apk-upgrade-deps \
      < "$tmp/input" > "$tmp/stdout" 2> "$tmp/stderr"
  ) || fail "canceling first-install dependency preparation should exit cleanly"

  [ ! -e "$tmp/home/apk-attempts" ] ||
    fail "canceling first install invoked apk"
  [ ! -e "$tmp/home/.codex-for-tui/install-consent" ] ||
    fail "canceling first install wrote consent"
  [ ! -e "$tmp/home/.local/bin/python3-test" ] ||
    fail "canceling first install created python3"
  assert_file_contains "$tmp/stdout" "已退出安装"
  rm -rf "$tmp"
}

test_generated_launcher_has_no_preflight_or_profile_refresh() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-launcher-no-preflight.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/bin"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$tmp/bin/codex-zh-bin"
  chmod +x "$tmp/bin/codex-zh-bin"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_write_launcher
  )

  assert_file_not_contains "$tmp/bin/codex" "--preflight"
  assert_file_not_contains "$tmp/bin/codex" "codex-local-resume"
  assert_file_not_contains "$tmp/bin/codex" "refresh"
  assert_file_not_contains "$tmp/bin/codex" "AGENTS.md"
  rm -rf "$tmp"
}

test_install_scripts_do_not_create_default_agents_md() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-no-default-agents.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_local_setup_agents
  )

  [ ! -e "$tmp/home/.codex/AGENTS.md" ] || fail "installer should not create default AGENTS.md"
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" "missing_agents"
  rm -rf "$tmp"
}

test_provider_name_normalization_keeps_custom_id_and_user_name() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-provider-name-normalize.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"

    cat > "$CODEX_HOME/config.toml" <<'EOF'
approval_policy = "never"
sandbox_mode = "danger-full-access"
model_provider = "custom"
model = "gpt-5.5"

[model_providers.custom]
name = "custom"
base_url = "https://api.example.test/v1"
wire_api = "responses"
EOF
    codex_config_repair_full_permission >"$tmp/stdout-legacy" 2>"$tmp/stderr-legacy"
    grep -F 'name = "OpenAI"' "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "legacy custom provider name should normalize to OpenAI"
    grep -F 'model_provider = "custom"' "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "provider id should remain custom"

    cat > "$CODEX_HOME/config.toml" <<'EOF'
approval_policy = "never"
sandbox_mode = "danger-full-access"
model_provider = "custom"
model = "gpt-5.5"

[model_providers.custom]
base_url = "https://api.example.test/v1"
wire_api = "responses"
EOF
    codex_config_normalize_third_party_provider_name "$CODEX_HOME/config.toml"
    grep -F 'name = "OpenAI"' "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "missing provider name should normalize to OpenAI"

    cat > "$CODEX_HOME/config.toml" <<'EOF'
approval_policy = "never"
sandbox_mode = "danger-full-access"
model_provider = "custom"
model = "gpt-5.5"

[model_providers.custom]
name = "Krill AI"
base_url = "https://api.example.test/v1"
wire_api = "responses"
EOF
    codex_config_normalize_third_party_provider_name "$CODEX_HOME/config.toml"
    grep -F 'name = "Krill AI"' "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "user provider name should be preserved"
    ! grep -F 'name = "OpenAI"' "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "user provider name should not be overwritten"

    cat > "$CODEX_HOME/config.toml" <<'EOF'
approval_policy = "never"
sandbox_mode = "danger-full-access"
model_provider = "custom"
model = "gpt-5.5"

[model_providers.custom]
name = 'Krill AI'
base_url = "https://api.example.test/v1"
wire_api = "responses"
EOF
    codex_config_normalize_third_party_provider_name "$CODEX_HOME/config.toml"
    grep -F "name = 'Krill AI'" "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "single-quoted user provider name should be preserved"
    ! grep -F 'name = "OpenAI"' "$CODEX_HOME/config.toml" >/dev/null 2>&1 ||
      fail "single-quoted user provider name should not be overwritten"
  ) || {
    sed -n '1,200p' "$tmp/stderr-legacy" >&2 || true
    fail "provider name normalization should complete"
  }

  rm -rf "$tmp"
}

test_repair_full_permission_adds_sandbox_mode() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-repair-permission.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex"
  cat > "$tmp/home/.codex/config.toml" <<'EOF'
approval_policy = "never"
model_provider = "custom"
model = "gpt-5.5"
EOF

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_config_repair_full_permission >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "repair full permission should complete"
  }

  assert_file_contains "$tmp/home/.codex/config.toml" 'approval_policy = "never"'
  assert_file_contains "$tmp/home/.codex/config.toml" 'sandbox_mode = "danger-full-access"'
  find "$tmp/home/.codex/install-state/backups" -type f -name config.toml | grep . >/dev/null 2>&1 ||
    fail "repair full permission should create a backup"
  rm -rf "$tmp"
}

test_proot_launcher_preserves_codex_args() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-proot-launcher.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/rootfs" "$tmp/bin"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    codex_local_write_proot_launcher "$tmp/bin/codex-alpine" "$tmp/rootfs"
  )

  assert_file_contains "$tmp/bin/codex-alpine" '/root/.local/bin/codex "$@"'
  assert_file_contains "$tmp/bin/codex-alpine" '-b "$HOME:/termux-home"'
  assert_file_not_contains "$tmp/bin/codex-alpine" 'set --'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" '请进入 rootfs 后运行 install-reterminal-alpine.sh'
  rm -rf "$tmp"
}

test_update_download_failure_is_error() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-update-failure.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"

  set +e
  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    . "$SCRIPT_DIR/lib/codex-zh-update.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_download_first_script() {
      return 1
    }
    codex_update_apply 1 >"$tmp/stdout" 2>"$tmp/stderr"
  )
  rc=$?
  set -e

  [ "$rc" -ne 0 ] || fail "codex_update_apply should fail when downloads fail"
  assert_file_contains "$tmp/stderr" "部分脚本更新失败"
  rm -rf "$tmp"
}

test_update_check_does_not_modify_installed_scripts() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-update-check-dry-run.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/share" "$tmp/bin"
  printf '%s\n' "old common" > "$tmp/share/lib-old-common"
  mkdir -p "$tmp/share/lib"
  printf '%s\n' "old common" > "$tmp/share/lib/codex-zh-common.sh"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    . "$SCRIPT_DIR/lib/codex-zh-update.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/share"
    codex_download_first_script() {
      stub_rel="$1"
      stub_dest="$2"
      mkdir -p "$(dirname "$stub_dest")"
      printf 'new body for %s\n' "$stub_rel" > "$stub_dest"
      chmod 755 "$stub_dest"
      return 0
    }
    codex_update_apply 1 >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "codex update check should complete as dry-run"
  }

  assert_file_contains "$tmp/share/lib/codex-zh-common.sh" "old common"
  assert_file_not_contains "$tmp/share/lib/codex-zh-common.sh" "new body"
  [ ! -e "$tmp/bin/codex-update" ] || fail "codex update check should not install command aliases"
  assert_file_contains "$tmp/stdout" "检测到脚本更新；运行 codex-update apply 执行更新。"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    . "$SCRIPT_DIR/lib/codex-zh-update.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/missing-share"
    codex_download_first_script() {
      stub_rel="$1"
      stub_dest="$2"
      mkdir -p "$(dirname "$stub_dest")"
      printf 'new body for %s\n' "$stub_rel" > "$stub_dest"
      chmod 755 "$stub_dest"
      return 0
    }
    codex_update_apply 1 >"$tmp/stdout-missing" 2>"$tmp/stderr-missing"
  ) || {
    sed -n '1,200p' "$tmp/stderr-missing" >&2 || true
    fail "codex update check should complete when install root is missing"
  }

  [ ! -e "$tmp/missing-share" ] || fail "codex update check should not create script install root"
  rm -rf "$tmp"
}

test_update_one_file_check_does_not_create_dest_dirs() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-update-one-dry-run.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"

  set +e
  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    . "$SCRIPT_DIR/lib/codex-zh-update.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_download_first_script() {
      stub_dest="$2"
      mkdir -p "$(dirname "$stub_dest")"
      printf 'new body\n' > "$stub_dest"
      return 0
    }
    codex_update_one_file "lib/codex-zh-common.sh" "$tmp/missing-share" 1 >"$tmp/stdout" 2>"$tmp/stderr"
  )
  rc=$?
  set -e

  [ "$rc" -eq 2 ] || fail "single-file update dry-run should report changed with rc=2"
  [ ! -e "$tmp/missing-share" ] || fail "single-file update dry-run should not create destination root"
  assert_file_contains "$tmp/stdout" "有更新：lib/codex-zh-common.sh"
  rm -rf "$tmp"
}

test_update_apply_refreshes_home_local_aliases() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-update-home-aliases.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.local/bin" "$tmp/install-bin" "$tmp/share"
  printf '#!/usr/bin/env sh\n# old codex-update\n' > "$tmp/home/.local/bin/codex-update"
  chmod 755 "$tmp/home/.local/bin/codex-update"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    . "$SCRIPT_DIR/lib/codex-zh-update.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/install-bin"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/share"
    codex_download_first_script() {
      stub_rel="$1"
      stub_dest="$2"
      mkdir -p "$(dirname "$stub_dest")"
      case "$stub_rel" in
        codex-update.sh)
          printf '#!/usr/bin/env sh\n# new codex-update supports 检查\n' > "$stub_dest"
          ;;
        *)
          printf '#!/usr/bin/env sh\n# new body for %s\n' "$stub_rel" > "$stub_dest"
          ;;
      esac
      chmod 755 "$stub_dest"
      return 0
    }
    codex_update_apply 0 >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,220p' "$tmp/stderr" >&2 || true
    fail "codex update apply should refresh home-local aliases too"
  }

  assert_file_contains "$tmp/install-bin/codex-update" "supports 检查"
  assert_file_contains "$tmp/home/.local/bin/codex-update" "supports 检查"
  [ -x "$tmp/home/.local/bin/codex-preview" ] || fail "home-local bridge wrappers should be refreshed"
  rm -rf "$tmp"
}

test_codex_local_status_accepts_official_marker() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-local-status-official.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/install-state" "$tmp/bin"
  printf '%s\n' "official-login" > "$tmp/home/.codex/install-state/official-login-mode"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$tmp/bin/codex-zh-bin"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$tmp/bin/codex"
  chmod +x "$tmp/bin/codex-zh-bin" "$tmp/bin/codex"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_status >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,120p' "$tmp/stderr" >&2 || true
    fail "codex local status should accept official login marker"
  }

  assert_file_not_contains "$tmp/stdout" "missing_config_or_official_login"
  rm -rf "$tmp"
}

test_partial_download_failure_is_not_accepted() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-partial-download.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/bin"

  cat > "$tmp/bin/curl" <<'EOF'
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
printf 'partial body\n' > "$dest"
exit 22
EOF
  chmod +x "$tmp/bin/curl"

  set +e
  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    export HOME="$tmp/home"
    export PATH="$tmp/bin:/bin:/usr/bin"
    codex_download_fetch_atomic "https://example.test/file.sh" "$tmp/out.sh"
  )
  rc=$?
  set -e

  [ "$rc" -ne 0 ] || fail "partial failed download should return nonzero"
  [ ! -e "$tmp/out.sh" ] || fail "partial failed download was moved into destination"
  [ ! -e "$tmp/out.sh.part" ] || fail "partial failed download was not cleaned up"
  rm -rf "$tmp"
}

test_self_test_fails_on_polluted_model_config() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-self-test-polluted-model.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/bin"

  cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env sh
# 配置模式
# 更新
printf 'codex-stub\n'
EOF
  chmod +x "$tmp/bin/codex"

  cat > "$tmp/bin/codex-update" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "$tmp/bin/codex-update"

  cat > "$tmp/bin/codex-local" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "$tmp/bin/codex-local"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
printf 'codex-zh 0.144.1\n'
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "$tmp/bin/curl"

  cat > "$tmp/home/.codex/config.toml" <<'EOF'
model_provider = "custom"
model = "可用模型：
gpt-5.5"
EOF

  set +e
  HOME="$tmp/home" \
  CODEX_HOME="$tmp/home/.codex" \
  CODEX_FOR_TUI_SELF_TEST_EXPECT_HOME="$tmp/home" \
  CODEX_FOR_TUI_SELF_TEST_EXPECT_CODEX_HOME="$tmp/home/.codex" \
  CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
  PATH="$tmp/bin:/bin:/usr/bin" \
    sh "$SCRIPT_DIR/codex-for-tui-self-test.sh" >"$tmp/stdout" 2>"$tmp/stderr"
  rc=$?
  set -e

  [ "$rc" -ne 0 ] || fail "self-test should fail when config model is polluted by menu text"
  assert_file_contains "$tmp/stderr" "model 值被菜单文字污染"
  rm -rf "$tmp"
}

test_no_startup_auto_refresh_symbols_remain() {
  if grep -R "auto_refresh_current_profile_on_start" "$SCRIPT_DIR" >/dev/null 2>&1; then
    fail "auto refresh startup symbol still exists"
  fi
  if grep -R "CODEX_ZH_AUTO_REFRESH_CURRENT_PROFILE" "$SCRIPT_DIR" >/dev/null 2>&1; then
    fail "auto refresh env still exists"
  fi
  if grep -R -- "--preflight-select" "$SCRIPT_DIR" >/dev/null 2>&1; then
    fail "old preflight startup option still exists"
  fi
  if grep -R -- "--refresh-current-profile" "$SCRIPT_DIR" >/dev/null 2>&1; then
    fail "old refresh-current-profile option still exists"
  fi
}

run_step test_syntax_and_asset_sync
run_step test_bootstrap_normal_start_does_not_fetch_when_codex_exists
run_step test_bootstrap_explicit_update_fetches_scripts
run_step test_bootstrap_prepares_python_dependency_with_retry
run_step test_bootstrap_dependency_failure_retries_on_next_start
run_step test_bootstrap_dependency_cancel_does_not_install
run_step test_generated_launcher_has_no_preflight_or_profile_refresh
run_step test_install_scripts_do_not_create_default_agents_md
run_step test_config_v2_smoke
run_step test_provider_name_normalization_keeps_custom_id_and_user_name
run_step test_repair_full_permission_adds_sandbox_mode
run_step test_proot_launcher_preserves_codex_args
run_step test_update_download_failure_is_error
run_step test_update_check_does_not_modify_installed_scripts
run_step test_update_one_file_check_does_not_create_dest_dirs
run_step test_update_apply_refreshes_home_local_aliases
run_step test_dev_transfer_smoke
run_step test_codex_local_status_accepts_official_marker
run_step test_partial_download_failure_is_not_accepted
run_step test_self_test_fails_on_polluted_model_config
run_step test_no_startup_auto_refresh_symbols_remain
printf 'OK: Codex for TUI refactor smoke tests passed\n'
