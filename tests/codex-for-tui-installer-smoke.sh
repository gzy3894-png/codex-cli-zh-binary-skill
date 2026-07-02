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
    export PATH="/bin:/usr/bin"
    sh "$BOOTSTRAP" >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,160p' "$tmp/stderr" >&2 || true
    fail "bootstrap normal start should launch local codex"
  }

  assert_file_contains "$tmp/stdout" "codex-ran"
  [ ! -e "$tmp/home/network.log" ] || fail "normal startup called network fetch"
  [ ! -e "$tmp/home/.codex-for-tui/remote/install-reterminal-alpine.sh" ] || fail "normal startup refreshed scripts"
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
  rm -rf "$tmp"
}

test_refresh_models_preserves_current_model_fields() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-refresh-preserve-model.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex"
  cat > "$tmp/home/.codex/config.toml" <<'EOF'
model_provider = "custom"
model = "manual-selected"
model_reasoning_effort = "high"
model_catalog_json = "/tmp/old-catalog.json"

[model_providers.custom]
base_url = "https://api.example.test/v1"
wire_api = "responses"
EOF
  printf '%s\n' '{"OPENAI_API_KEY":"sk-test"}' > "$tmp/home/.codex/auth.json"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_config_fetch_models() {
      cat > "$3" <<'EOF'
{
  "data": [
    {"id":"manual-selected"},
    {"id":"new-remote-model"}
  ]
}
EOF
      : > "$4"
      return 0
    }
    codex_config_refresh_models >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "refresh-models should complete"
  }

  assert_file_contains "$tmp/home/.codex/config.toml" 'model = "manual-selected"'
  assert_file_contains "$tmp/home/.codex/config.toml" 'model_reasoning_effort = "high"'
  assert_file_contains "$tmp/home/.codex/config.toml" 'model_catalog_json = "/tmp/old-catalog.json"'
  assert_file_contains "/tmp/old-catalog.json" '"slug": "new-remote-model"'
  rm -f /tmp/old-catalog.json
  rm -rf "$tmp"
}

test_interactive_model_choice_writes_only_model_id() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-interactive-model-choice.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_FORCE_STDIN=1
    codex_config_fetch_models() {
      cat > "$3" <<'EOF'
{
  "data": [
    {"id":"gpt-5.4"},
    {"id":"gpt-5.5"}
  ]
}
EOF
      : > "$4"
      return 0
    }
    printf '%s\n%s\n%s\n' "https://api.example.test" "sk-test" "2" |
      codex_config_prompt_third_party >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "interactive third-party setup should complete"
  }

  assert_file_contains "$tmp/home/.codex/config.toml" 'model = "gpt-5.5"'
  assert_file_not_contains "$tmp/home/.codex/config.toml" "可用模型"
  assert_file_contains "$tmp/stderr" "可用模型"
  rm -rf "$tmp"
}

test_model_catalog_uses_current_codex_schema_shapes() {
  tmp="${TMPDIR:-/tmp}/codex-tui-test-model-catalog-enum.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"
  printf '%s\n' "gpt-5.5" > "$tmp/models.txt"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_config_write_model_catalog "$tmp/models.txt" "gpt-5.5" "$tmp/model_catalog.json"
  )

  assert_file_not_contains "$tmp/model_catalog.json" '"web_search_tool_type": "web_search"'
  assert_file_contains "$tmp/model_catalog.json" '"web_search_tool_type": "text"'
  assert_file_not_contains "$tmp/model_catalog.json" '"supported_reasoning_levels": ["minimal"'
  assert_file_contains "$tmp/model_catalog.json" '"effort": "minimal"'
  assert_file_contains "$tmp/model_catalog.json" '"description": "minimal"'
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
printf 'codex-zh 0.142.4\n'
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
run_step test_generated_launcher_has_no_preflight_or_profile_refresh
run_step test_refresh_models_preserves_current_model_fields
run_step test_interactive_model_choice_writes_only_model_id
run_step test_model_catalog_uses_current_codex_schema_shapes
run_step test_proot_launcher_preserves_codex_args
run_step test_update_download_failure_is_error
run_step test_partial_download_failure_is_not_accepted
run_step test_self_test_fails_on_polluted_model_config
run_step test_no_startup_auto_refresh_symbols_remain
printf 'OK: Codex for TUI refactor smoke tests passed\n'
