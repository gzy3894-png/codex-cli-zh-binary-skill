#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-v2-ui.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  file="$1"
  pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "missing '$pattern' in $file"
}

assert_not_contains() {
  file="$1"
  pattern="$2"
  ! grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "unexpected '$pattern' in $file"
}

json_assert() {
  file="$1"
  expression="$2"
  python3 - "$file" "$expression" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
if not eval(sys.argv[2], {"__builtins__": {}, "len": len}, {"v": value}):
    raise SystemExit(f"JSON assertion failed: {sys.argv[2]}")
PY
}

runtime_hash() {
  hash_home="$1"
  {
    for file in \
      "$hash_home/config.toml" \
      "$hash_home/auth.json" \
      "$hash_home/model_catalog.json" \
      "$hash_home/config-profiles-v2/index.json"
    do
      if [ -f "$file" ]; then
        sha256sum "$file"
      else
        printf 'missing  %s\n' "$file"
      fi
    done
    if [ -d "$hash_home/config-profiles-v2/profiles" ]; then
      find "$hash_home/config-profiles-v2/profiles" -type f -print |
        LC_ALL=C sort |
        while IFS= read -r file; do
          sha256sum "$file"
        done
    fi
  } | sha256sum | awk '{print $1}'
}

test_menu_switch_view_delete_and_invalid_choice() (
  tmp="$TMP_ROOT/menu-routing"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_v2_prepare
  codex_config_v2_run "$tmp/create-alpha.json" \
    profile create \
    --name alpha \
    --mode official \
    --model gpt-5.4 \
    --reasoning-effort high \
    --activate
  codex_config_v2_run "$tmp/create-omega.json" \
    profile create \
    --name omega \
    --mode official \
    --model gpt-5.5 \
    --reasoning-effort xhigh

  printf '99\n4\n99\n2\n2\n99\n2\n9\n' |
    codex_config_menu > "$tmp/switch.out" 2> "$tmp/switch.err"
  codex_config_engine profile show omega > "$tmp/omega-active.json"
  codex_config_engine profile show alpha > "$tmp/alpha-inactive.json"
  json_assert "$tmp/omega-active.json" "v['active'] is True and v['profile']['model'] == 'gpt-5.5'"
  json_assert "$tmp/alpha-inactive.json" "v['active'] is False"
  assert_contains "$tmp/switch.err" "请输入 0 到 9，或输入 b 返回。"
  assert_contains "$tmp/switch.err" "中转站编号超出范围。"
  assert_contains "$tmp/switch.err" "名称: omega"
  assert_contains "$tmp/switch.out" "已切换配置：omega"

  printf '5\n1\nn\n9\n' |
    codex_config_menu > "$tmp/delete-cancel.out" 2> "$tmp/delete-cancel.err"
  codex_config_engine profile list > "$tmp/after-cancel.json"
  json_assert "$tmp/after-cancel.json" "len(v['profiles']) == 2 and v['profiles'][0]['name'] == 'alpha' and v['profiles'][1]['name'] == 'omega'"
  assert_contains "$tmp/delete-cancel.err" "确认删除配置 alpha"
  assert_not_contains "$tmp/delete-cancel.out" "已删除配置：alpha"

  printf '5\n1\ny\n9\n' |
    codex_config_menu > "$tmp/delete-confirm.out" 2> "$tmp/delete-confirm.err"
  codex_config_engine profile list > "$tmp/after-delete.json"
  json_assert "$tmp/after-delete.json" "len(v['profiles']) == 1 and v['profiles'][0]['name'] == 'omega'"
  assert_contains "$tmp/delete-confirm.out" "已删除配置：alpha"
)

test_back_navigation_and_non_destructive_exit() (
  tmp="$TMP_ROOT/back-navigation"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_v2_prepare
  codex_config_v2_run "$tmp/create-alpha.json" \
    profile create \
    --name alpha \
    --mode official \
    --model gpt-5.4 \
    --reasoning-effort high \
    --activate

  before="$(runtime_hash "$CODEX_HOME")"
  printf '1\nb\n1\n2\nb\n2\nb\n3\nb\n4\nb\n5\nb\n7\nb\nb\n' |
    codex_config_menu > "$tmp/back.out" 2> "$tmp/back.err"
  after_back="$(runtime_hash "$CODEX_HOME")"
  [ "$before" = "$after_back" ] ||
    fail "layered back navigation changed runtime configuration"
  assert_contains "$tmp/back.err" "新建配置："
  assert_contains "$tmp/back.err" "配置名称"
  assert_contains "$tmp/back.err" "请选择要切换的配置编号"
  assert_contains "$tmp/back.err" "请选择要编辑的中转站编号"
  assert_contains "$tmp/back.err" "请选择要查看的配置编号"
  assert_contains "$tmp/back.err" "请选择要删除的配置编号"
  assert_contains "$tmp/back.err" "请选择压缩策略"

  printf '0\n' |
    codex_config_menu > "$tmp/exit.out" 2> "$tmp/exit.err"
  after_exit="$(runtime_hash "$CODEX_HOME")"
  [ "$before" = "$after_exit" ] ||
    fail "explicit config-mode exit changed runtime configuration"
  assert_contains "$tmp/exit.out" "已退出配置模式。"
)

test_official_create_and_same_id_edit() (
  tmp="$TMP_ROOT/official"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  export CODEX_ZH_DEFAULT_MODEL=gpt-5.6-sol
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_v2_prepare
  printf 'official\n99\n1\n6\n\n' |
    codex_config_v2_create_official > "$tmp/create.out" 2> "$tmp/create.err"
  codex_config_engine profile show official > "$tmp/before-edit.json"
  profile_id="$(codex_config_v2_json_value "$tmp/before-edit.json" profile.id)"
  json_assert "$tmp/before-edit.json" "v['profile']['model'] == 'gpt-5.6-sol' and v['profile']['reasoning_effort'] == 'ultra'"
  assert_contains "$tmp/create.err" "模型编号超出范围"

  # Field-level edit: pick station → 2=模型策略 → keep model → reasoning 5=max → confirm
  printf '1\n2\n\n5\n\n' |
    codex_config_v2_edit_menu > "$tmp/edit.out" 2> "$tmp/edit.err"
  codex_config_engine profile show official > "$tmp/after-edit.json"
  json_assert "$tmp/after-edit.json" "v['profile']['id'] == '$profile_id' and v['profile']['name'] == 'official' and v['profile']['reasoning_effort'] == 'max'"
  codex_config_engine profile list > "$tmp/list.json"
  json_assert "$tmp/list.json" "len(v['profiles']) == 1"
  assert_contains "$CODEX_HOME/config.toml" 'approval_policy = "never"'
  assert_contains "$CODEX_HOME/config.toml" 'sandbox_mode = "danger-full-access"'
)

test_third_party_create_refresh_and_secret_redaction() (
  tmp="$TMP_ROOT/third-party"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  export CODEX_CONFIG_CATALOG_OFFLINE=1
  export CODEX_ZH_DEFAULT_MODEL=gpt-5.6-sol
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_fetch_models() {
    [ "$1" = "https://api.krill-ai.com/codex/v1" ] ||
      fail "refresh used the wrong provider base URL: $1"
    printf '%s\n' \
      '{"data":[{"id":"gpt-5.4"},{"id":"gpt-5.6-sol"},{"id":"vendor-unknown"}]}' > "$3"
    : > "$4"
  }

  codex_config_v2_prepare
  printf 'krill\nhttps://api.krill-ai.com/codex/v1\nsecret-redaction-check\n\n6\n\n' |
    codex_config_v2_create_third_party > "$tmp/create.out" 2> "$tmp/create.err"
  codex_config_engine profile show krill > "$tmp/show.json"
  assert_not_contains "$tmp/create.out" "secret-redaction-check"
  assert_not_contains "$tmp/create.err" "secret-redaction-check"
  assert_not_contains "$tmp/show.json" "secret-redaction-check"
  assert_contains "$CODEX_HOME/auth.json" "secret-redaction-check"
  json_assert "$tmp/show.json" "v['profile']['model'] == 'gpt-5.6-sol' and v['profile']['reasoning_effort'] == 'ultra' and v['profile']['has_catalog'] is True"

  codex_config_refresh_models > "$tmp/refresh.out" 2> "$tmp/refresh.err"
  codex_config_engine profile show krill > "$tmp/refreshed.json"
  json_assert "$tmp/refreshed.json" "v['profile']['model'] == 'gpt-5.6-sol' and v['profile']['reasoning_effort'] == 'ultra'"
)

test_runtime_dirty_sync_signal() (
  tmp="$TMP_ROOT/dirty"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_v2_prepare
  codex_config_v2_run "$tmp/create.json" \
    profile create \
    --name official \
    --mode official \
    --model gpt-5.4 \
    --reasoning-effort high \
    --activate
  sed -i 's/model = "gpt-5.4"/model = "gpt-5.5"/' "$CODEX_HOME/config.toml"
  codex_config_engine status > "$tmp/dirty.json"
  json_assert "$tmp/dirty.json" "v['runtime_dirty'] is True and 'model' in v['runtime_dirty_reasons']"

  printf '1\n' |
    codex_config_v2_dirty_guard "测试切换" > "$tmp/sync.out" 2> "$tmp/sync.err"
  codex_config_engine status > "$tmp/clean.json"
  codex_config_engine profile show official > "$tmp/synced.json"
  json_assert "$tmp/clean.json" "v['runtime_dirty'] is False"
  json_assert "$tmp/synced.json" "v['profile']['model'] == 'gpt-5.5'"
  assert_contains "$tmp/sync.err" "同步到当前配置档"
)

test_runtime_dirty_save_as_new_from_menu() (
  tmp="$TMP_ROOT/dirty-save-as"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_v2_prepare
  codex_config_v2_run "$tmp/create.json" \
    profile create \
    --name original \
    --mode official \
    --model gpt-5.4 \
    --reasoning-effort high \
    --activate
  sed -i 's/model = "gpt-5.4"/model = "gpt-5.5"/' "$CODEX_HOME/config.toml"

  printf '9\n2\nruntime-copy\n' |
    codex_config_menu > "$tmp/save-as.out" 2> "$tmp/save-as.err"
  codex_config_engine status > "$tmp/status.json"
  codex_config_engine profile list > "$tmp/list.json"
  codex_config_engine profile show original > "$tmp/original.json"
  codex_config_engine profile show runtime-copy > "$tmp/runtime-copy.json"
  json_assert "$tmp/status.json" "v['runtime_dirty'] is False"
  json_assert "$tmp/list.json" "len(v['profiles']) == 2"
  json_assert "$tmp/original.json" "v['active'] is False and v['profile']['model'] == 'gpt-5.4'"
  json_assert "$tmp/runtime-copy.json" "v['active'] is True and v['profile']['model'] == 'gpt-5.5'"
  assert_contains "$tmp/save-as.err" "运行配置有未保存变化"
  assert_contains "$tmp/save-as.err" "2. 另存为新配置档"
  assert_contains "$tmp/save-as.err" "新配置名称"
)

test_runtime_dirty_continue_without_saving_from_menu() (
  tmp="$TMP_ROOT/dirty-continue"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
  export CODEX_ZH_FORCE_STDIN=1
  mkdir -p "$HOME"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-download.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_config_v2_prepare
  codex_config_v2_run "$tmp/create.json" \
    profile create \
    --name original \
    --mode official \
    --model gpt-5.4 \
    --reasoning-effort high \
    --activate
  sed -i 's/model = "gpt-5.4"/model = "gpt-5.5"/' "$CODEX_HOME/config.toml"
  before="$(runtime_hash "$CODEX_HOME")"

  printf '9\n3\n' |
    codex_config_menu > "$tmp/continue.out" 2> "$tmp/continue.err"
  after="$(runtime_hash "$CODEX_HOME")"
  [ "$before" = "$after" ] ||
    fail "continue-without-saving changed runtime or profile files"
  codex_config_engine status > "$tmp/status.json"
  codex_config_engine profile show original > "$tmp/original.json"
  json_assert "$tmp/status.json" "v['runtime_dirty'] is True and 'model' in v['runtime_dirty_reasons']"
  json_assert "$tmp/original.json" "v['active'] is True and v['profile']['model'] == 'gpt-5.4'"
  assert_contains "$CODEX_HOME/config.toml" 'model = "gpt-5.5"'
  assert_contains "$tmp/continue.err" "3. 暂不保存，继续"
)

test_explicit_config_bootstraps_missing_engine_assets() (
  tmp="$TMP_ROOT/bootstrap-assets"
  export HOME="$tmp/home"
  export CODEX_HOME="$tmp/home/.codex"
  export CODEX_ZH_STATE_ROOT="$CODEX_HOME/install-state"
  export CODEX_ZH_ACTIVE_SCRIPT_DIR="$tmp/missing-active-root"
  export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/installed-scripts"
  export CODEX_ZH_SCRIPT_CACHE_ROOT="$tmp/cache-scripts"
  export CODEX_ZH_FORCE_STDIN=1
  mkdir -p "$HOME" "$CODEX_ZH_ACTIVE_SCRIPT_DIR"
  . "$SCRIPT_DIR/lib/codex-zh-common.sh"
  . "$SCRIPT_DIR/lib/codex-zh-config.sh"

  codex_download_first_script() {
    mkdir -p "$(dirname "$2")"
    cp "$SCRIPT_DIR/$1" "$2"
  }

  codex_config_v2_prepare > "$tmp/stdout" 2> "$tmp/stderr"
  [ -x "$CODEX_ZH_SCRIPT_INSTALL_ROOT/libexec/codex-config-engine.py" ] ||
    fail "explicit config did not bootstrap the engine"
  [ -s "$CODEX_ZH_SCRIPT_INSTALL_ROOT/data/openai-models.json" ] ||
    fail "explicit config did not bootstrap the model mirror"
  [ -s "$CODEX_ZH_SCRIPT_INSTALL_ROOT/vendor/python/tomlkit/parser.py" ] ||
    fail "explicit config did not bootstrap bundled tomlkit"
  assert_contains "$tmp/stdout" "配置引擎资源缺失"
)

printf 'RUN menu switch, view, delete and invalid choices\n'
test_menu_switch_view_delete_and_invalid_choice
printf 'RUN layered back navigation and non-destructive exit\n'
test_back_navigation_and_non_destructive_exit
printf 'RUN official create and same-ID edit\n'
test_official_create_and_same_id_edit
printf 'RUN third-party create, refresh and secret redaction\n'
test_third_party_create_refresh_and_secret_redaction
printf 'RUN runtime dirty sync signal\n'
test_runtime_dirty_sync_signal
printf 'RUN runtime dirty save-as-new menu path\n'
test_runtime_dirty_save_as_new_from_menu
printf 'RUN runtime dirty continue-without-saving menu path\n'
test_runtime_dirty_continue_without_saving_from_menu
printf 'RUN explicit config bootstraps missing engine assets\n'
test_explicit_config_bootstraps_missing_engine_assets
printf 'OK: Codex for TUI config V2 UI smoke tests passed\n'
