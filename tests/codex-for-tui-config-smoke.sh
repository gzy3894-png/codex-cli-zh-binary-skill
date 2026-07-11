#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"

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

assert_file_missing() {
  file="$1"
  [ ! -e "$file" ] || fail "expected file to be absent: $file"
}

run_step() {
  name="$1"
  printf 'RUN %s\n' "$name"
  "$name"
}

write_real_codex_stub() {
  bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
printf 'real-codex-ran'
if [ "$#" -gt 0 ]; then
  printf ' %s' "$@"
fi
printf '\n'
EOF
  chmod 755 "$bin_dir/codex-zh-bin"
}

write_hook_tool_stubs() {
  bin_dir="$1"
  mkdir -p "$bin_dir"
  for tool in codex-rtk codex-context; do
    cat > "$bin_dir/$tool" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in
  status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod 755 "$bin_dir/$tool"
  done
}

write_launcher() {
  tmp="$1"
  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_write_launcher
  )
}

prepare_v2_profile() {
  tmp="$1"
  PYTHONNOUSERSITE=1 python3 "$SCRIPT_DIR/libexec/codex-config-engine.py" \
    --codex-home "$tmp/home/.codex" \
    profile create \
    --name existing \
    --mode official \
    --model gpt-5.4 \
    --activate >/dev/null
}

test_normal_codex_start_preserves_existing_config() {
  tmp="${TMPDIR:-/tmp}/codex-tui-config-normal-readonly.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/bin" "$tmp/home/.codex"
  printf '%s\n' 'configured = true' > "$tmp/home/.codex/config.toml"
  prepare_v2_profile "$tmp"
  before_config="$(sha256sum "$tmp/home/.codex/config.toml" | awk '{print $1}')"
  write_real_codex_stub "$tmp/bin"
  write_launcher "$tmp"

  (
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR"
    export CODEX_FOR_TUI_HOOK_AUTH_PROMPT=0
    export CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT=0
    PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}" "$tmp/bin/codex" >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,160p' "$tmp/stderr" >&2 || true
    fail "normal codex startup should exec the real binary"
  }

  assert_file_contains "$tmp/stdout" "real-codex-ran"
  assert_file_contains "$tmp/home/.codex/config.toml" "configured = true"
  [ "$before_config" = "$(sha256sum "$tmp/home/.codex/config.toml" | awk '{print $1}')" ] ||
    fail "normal Codex startup changed the control config"
  assert_file_missing "$tmp/home/.codex/auth.json"
  assert_file_missing "$tmp/home/.codex/model_catalog.json"
  rm -rf "$tmp"
}

test_hook_quick_auth_writes_only_after_explicit_choice_and_backs_up() {
  tmp="${TMPDIR:-/tmp}/codex-tui-config-hook-auth.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/bin" "$tmp/home/.codex" "$tmp/etc"
  req="$tmp/etc/requirements.toml"
  printf '%s\n' 'configured = true' > "$tmp/home/.codex/config.toml"
  prepare_v2_profile "$tmp"
  write_real_codex_stub "$tmp/bin"
  write_hook_tool_stubs "$tmp/bin"
  write_hook_tool_stubs "$tmp/home/.local/bin"
  write_launcher "$tmp"

  (
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_REQUIREMENTS_FILE="$req"
    export PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}"
    printf '\n' | "$tmp/bin/codex" >"$tmp/stdout-skip" 2>"$tmp/stderr-skip"
  ) || {
    sed -n '1,200p' "$tmp/stderr-skip" >&2 || true
    fail "skipping quick auth by default should still start codex"
  }

  assert_file_contains "$tmp/stdout-skip" "real-codex-ran"
  assert_file_missing "$req"
  assert_file_contains "$tmp/home/.codex/config.toml" "configured = true"
  # Some CI shells have no usable tty and may skip the prompt entirely; the
  # safety contract is behavioral: default/no explicit 1 must not write hooks.

  bad_parent="$tmp/not-a-dir"
  printf '%s\n' "not a directory" > "$bad_parent"
  (
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_REQUIREMENTS_FILE="$bad_parent/requirements.toml"
    export PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}"
    printf '1\n' | "$tmp/bin/codex" >"$tmp/stdout-auth-fail" 2>"$tmp/stderr-auth-fail"
  ) || {
    sed -n '1,240p' "$tmp/stderr-auth-fail" >&2 || true
    fail "failed quick auth should warn and continue normal startup"
  }
  assert_file_contains "$tmp/stdout-auth-fail" "real-codex-ran"
  assert_file_contains "$tmp/stderr-auth-fail" "快捷授权失败"

  printf '%s\n' "existing_requirement = true" > "$req"
  (
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR"
    export CODEX_ZH_FORCE_STDIN=1
    export CODEX_FOR_TUI_REQUIREMENTS_FILE="$req"
    export PATH="$tmp/bin:/bin:/usr/bin:${PATH:-}"
    printf '1\n' | "$tmp/bin/codex" >"$tmp/stdout-auth" 2>"$tmp/stderr-auth"
  ) || {
    sed -n '1,240p' "$tmp/stderr-auth" >&2 || true
    fail "explicit quick auth should start codex"
  }

  assert_file_contains "$tmp/stdout-auth" "real-codex-ran"
  assert_file_contains "$req" "existing_requirement = true"
  assert_file_contains "$req" "# codex-for-tui-managed-hooks begin"
  assert_file_contains "$req" 'command = "codex-rtk hook"'
  assert_file_contains "$req" 'command = "codex-context hook"'
  assert_file_contains "$tmp/home/.codex/config.toml" "configured = true"
  find "$tmp/home/.codex" -type f -path '*/install-state/backups/*/requirements.toml' \
    -exec grep -l 'existing_requirement = true' {} \; |
    grep . >/dev/null 2>&1 || fail "requirements.toml backup was not recoverable"
  if find "$tmp" \( -name '*.tmp.*' -o -name '*.strip-*' \) -print | grep . >/dev/null 2>&1; then
    fail "temporary config files should not remain after atomic writes"
  fi
  rm -rf "$tmp"
}

run_step test_normal_codex_start_preserves_existing_config
run_step test_hook_quick_auth_writes_only_after_explicit_choice_and_backs_up
printf 'OK: Codex for TUI config smoke tests passed\n'
