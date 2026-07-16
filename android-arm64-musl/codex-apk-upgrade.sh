#!/usr/bin/env sh
set -eu

RELEASE="2.5.28"
VERSION_CODE="94"
EXPECTED_CODEX_VERSION="0.144.1"
EXPECTED_TARGET="aarch64-unknown-linux-musl"
EXPECTED_ARCHIVE_SHA256="1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61"
EXPECTED_BINARY_SHA256="0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767"

HOME="${HOME:-/root}"
CONTROL_HOME="${CODEX_APK_UPGRADE_CODEX_HOME:-$HOME/.codex}"
export CODEX_HOME="$CONTROL_HOME"
INSTALL_DIR="${CODEX_APK_UPGRADE_INSTALL_DIR:-/usr/local/bin}"
SCRIPT_ROOT="${CODEX_APK_UPGRADE_SCRIPT_ROOT:-$HOME/.local/share/codex-zh/scripts}"
STATE_ROOT="${CODEX_APK_UPGRADE_STATE_ROOT:-$CONTROL_HOME/install-state}"
RELEASE_STATE="$STATE_ROOT/apk-upgrades/$RELEASE"
LOCK_DIR="$STATE_ROOT/apk-upgrade.lock"
COMPLETE_MARKER="$RELEASE_STATE/complete"
JOURNAL="$RELEASE_STATE/transaction"
MANAGED_BACKUP="$RELEASE_STATE/rollback-managed"
WORK_ROOT="$RELEASE_STATE/work"
ASSET_PREFIX="assets/codex-upgrade"
ASSET_DIR="${CODEX_APK_UPGRADE_ASSET_DIR:-}"
PKG_PATH="${PKG_PATH:-}"
UPGRADE_ACTIVE=0
LOCK_HELD=0
CONFIG_BACKUP=""
STAGED_ENGINE=""
WORKSPACE_BACKUP=""
WORKSPACE_MIGRATOR=""
SESSION_DEFAULTS_ADAPTER=""

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '警告: %s\n' "$*" >&2
}

fail() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

verify_sha256() {
  file="$1"
  expected="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  actual="$(sha256_file "$file")"
  [ "$actual" = "$expected" ] ||
    fail "SHA256 不匹配：$file，实际 $actual，期望 $expected"
}

manifest_value() {
  key="$1"
  sed -n "s/^${key}=//p" "$WORK_ROOT/manifest.properties" | sed -n '1p'
}

safe_asset_name() {
  case "$1" in
    ""|/*|*..*|*\\*) return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

copy_asset() {
  relative="$1"
  destination="$2"
  safe_asset_name "$relative" || fail "APK 载荷名称无效：$relative"
  mkdir -p "$(dirname "$destination")"
  temporary="$destination.part.$$"
  rm -f "$temporary"
  if [ -n "$ASSET_DIR" ]; then
    [ -r "$ASSET_DIR/$relative" ] || fail "APK 测试载荷缺失：$relative"
    cp "$ASSET_DIR/$relative" "$temporary"
  else
    [ -n "$PKG_PATH" ] && [ -r "$PKG_PATH" ] ||
      fail "无法读取当前 APK 路径，拒绝启动半升级环境"
    unzip -p "$PKG_PATH" "$ASSET_PREFIX/$relative" > "$temporary" ||
      fail "无法从 APK 提取载荷：$relative"
  fi
  [ -s "$temporary" ] || fail "APK 载荷为空：$relative"
  mv "$temporary" "$destination"
}

quick_complete() {
  [ -s "$COMPLETE_MARKER" ] || return 1
  grep -F -x "release=$RELEASE" "$COMPLETE_MARKER" >/dev/null 2>&1 || return 1
  grep -F -x "version_code=$VERSION_CODE" "$COMPLETE_MARKER" >/dev/null 2>&1 || return 1
  [ -x "$INSTALL_DIR/codex-zh-bin" ] || return 1
  [ -x "$INSTALL_DIR/codex" ] || return 1
  [ -x "$INSTALL_DIR/codex-session-defaults" ] || return 1
  [ -s "$SCRIPT_ROOT/libexec/codex-config-engine.py" ] || return 1
  return 0
}

best_effort_refresh() {
  [ "${CODEX_APK_UPGRADE_SKIP_REFRESH:-0}" != "1" ] || return 0
  [ -s "$RELEASE_STATE/refresh-attempted" ] && return 0
  engine="$SCRIPT_ROOT/libexec/codex-config-engine.py"
  [ -s "$engine" ] && command -v python3 >/dev/null 2>&1 || return 0
  # Quiet by default after upgrade; only surface failures.
  if PYTHONNOUSERSITE=1 python3 "$engine" \
    --codex-home "$CONTROL_HOME" apk-refresh-active --timeout 8 \
    > "$RELEASE_STATE/refresh.json" 2> "$RELEASE_STATE/refresh.err"
  then
    printf 'ok %s\n' "$(date '+%s' 2>/dev/null || printf unknown)" \
      > "$RELEASE_STATE/refresh-attempted"
  else
    printf 'failed %s\n' "$(date '+%s' 2>/dev/null || printf unknown)" \
      > "$RELEASE_STATE/refresh-attempted"
    warn "第三方模型目录联网刷新失败，已保留离线重建结果。"
  fi
}

refresh_existing_hook_blocks() {
  [ "${CODEX_APK_UPGRADE_SKIP_HOOK_REFRESH:-0}" != "1" ] || return 0
  (
    export HOME CODEX_HOME="$CONTROL_HOME"
    export PATH="$INSTALL_DIR:$PATH"
    if codex_config_managed_hooks_enabled; then
      codex_config_ensure_managed_hooks
      exit 0
    fi
    config="$CONTROL_HOME/config.toml"
    [ -f "$config" ] || exit 0
    if grep -F '# codex-for-tui-rtk-hook begin' "$config" >/dev/null 2>&1 ||
      grep -F '# codex-for-tui-context-hook begin' "$config" >/dev/null 2>&1 ||
      grep -F '# codex-for-tui-session-defaults-hook begin' "$config" >/dev/null 2>&1
    then
      codex_config_ensure_default_hooks
    fi
  )
}

process_start_token() {
  pid="$1"
  awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true
}

release_lock() {
  if [ "$LOCK_HELD" = "1" ]; then
    rm -f "$LOCK_DIR/pid" "$LOCK_DIR/start" "$LOCK_DIR/release" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

acquire_lock() {
  mkdir -p "$STATE_ROOT" "$RELEASE_STATE"
  waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if quick_complete; then
      return 2
    fi
    holder="$(sed -n '1p' "$LOCK_DIR/pid" 2>/dev/null || true)"
    case "$holder" in
      ""|*[!0-9]*)
        holder=""
        ;;
    esac
    holder_start="$(sed -n '1p' "$LOCK_DIR/start" 2>/dev/null || true)"
    current_start=""
    [ -z "$holder" ] || current_start="$(process_start_token "$holder")"
    if {
      [ -n "$holder" ] &&
        { ! kill -0 "$holder" 2>/dev/null || [ -z "$holder_start" ] ||
          [ "$holder_start" != "$current_start" ]; }
    } || {
      [ -z "$holder" ] && [ "$waited" -ge 2 ]
    }; then
      rm -f "$LOCK_DIR/pid" "$LOCK_DIR/start" "$LOCK_DIR/release" 2>/dev/null || true
      rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    [ "$waited" -lt "${CODEX_APK_UPGRADE_LOCK_WAIT_SECONDS:-180}" ] ||
      fail "等待 APK 环境升级锁超时：$LOCK_DIR"
    sleep 1
    waited=$((waited + 1))
  done
  LOCK_HELD=1
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  printf '%s\n' "$(process_start_token "$$")" > "$LOCK_DIR/start"
  printf '%s\n' "$RELEASE" > "$LOCK_DIR/release"
  return 0
}

restore_managed() {
  [ -d "$MANAGED_BACKUP" ] || return 0
  if [ -s "$MANAGED_BACKUP/managed-files" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      rm -f "$INSTALL_DIR/$name" 2>/dev/null || true
      if [ -e "$MANAGED_BACKUP/bin/$name" ] || [ -L "$MANAGED_BACKUP/bin/$name" ]; then
        cp -a "$MANAGED_BACKUP/bin/$name" "$INSTALL_DIR/$name"
      fi
    done < "$MANAGED_BACKUP/managed-files"
  fi
  rm -rf "$SCRIPT_ROOT"
  if [ -d "$MANAGED_BACKUP/scripts" ]; then
    mkdir -p "$(dirname "$SCRIPT_ROOT")"
    cp -a "$MANAGED_BACKUP/scripts" "$SCRIPT_ROOT"
  fi
}

rollback_config() {
  [ -n "$CONFIG_BACKUP" ] || return 0
  [ -s "$STAGED_ENGINE" ] || return 0
  PYTHONNOUSERSITE=1 python3 "$STAGED_ENGINE" \
    --codex-home "$CONTROL_HOME" apk-rollback --backup "$CONFIG_BACKUP" \
    > "$RELEASE_STATE/rollback-config.json" 2> "$RELEASE_STATE/rollback-config.err" ||
    warn "配置恢复点自动回滚失败：$CONFIG_BACKUP"
}

rollback_workspace() {
  [ -n "$WORKSPACE_BACKUP" ] || return 0
  [ -s "$WORKSPACE_MIGRATOR" ] || return 0
  PYTHONNOUSERSITE=1 python3 "$WORKSPACE_MIGRATOR" \
    --codex-home "$CONTROL_HOME" rollback --backup "$WORKSPACE_BACKUP" \
    > "$RELEASE_STATE/rollback-workspace.json" 2> "$RELEASE_STATE/rollback-workspace.err" ||
    warn "工作区迁移自动回滚失败：$WORKSPACE_BACKUP"
}

finish() {
  rc=$?
  trap - EXIT HUP INT TERM
  if [ "$rc" -ne 0 ] && [ "$UPGRADE_ACTIVE" = "1" ]; then
    warn "APK 环境升级失败，正在恢复升级前状态。"
    rollback_workspace
    rollback_config
    restore_managed
    {
      printf 'release=%s\n' "$RELEASE"
      printf 'failed_at=%s\n' "$(date '+%s' 2>/dev/null || printf unknown)"
      printf 'exit_code=%s\n' "$rc"
    } > "$RELEASE_STATE/failed"
    rm -f "$COMPLETE_MARKER"
  fi
  release_lock
  exit "$rc"
}

trap finish EXIT HUP INT TERM

# Daily cold start: upgrade already complete — exit immediately without network
# model refresh (that only runs once after a real upgrade transaction).
if quick_complete; then
  exit 0
fi

if acquire_lock; then
  :
else
  lock_rc=$?
  if [ "$lock_rc" -eq 2 ]; then
    # Another process finished the upgrade while we waited.
    exit 0
  fi
  exit "$lock_rc"
fi

if quick_complete; then
  exit 0
fi

if [ "${CODEX_APK_UPGRADE_ALLOW_TEST_PAYLOAD:-0}" = "1" ] &&
  [ -n "${CODEX_APK_UPGRADE_TEST_HOLD_SECONDS:-}" ]
then
  sleep "$CODEX_APK_UPGRADE_TEST_HOLD_SECONDS"
fi

UPGRADE_ACTIVE=1
rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT"

copy_asset "manifest.properties" "$WORK_ROOT/manifest.properties"
copy_asset "manifest.sha256" "$WORK_ROOT/manifest.sha256"
manifest_expected="$(awk 'NR == 1 {print tolower($1)}' "$WORK_ROOT/manifest.sha256")"
case "$manifest_expected" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
    ;;
  *) fail "APK 升级 manifest SHA 格式无效" ;;
esac
verify_sha256 "$WORK_ROOT/manifest.properties" "$manifest_expected"

manifest_release="$(manifest_value release)"
manifest_version_code="$(manifest_value version_code)"
manifest_codex_version="$(manifest_value codex_version)"
manifest_target="$(manifest_value target)"
support_archive="$(manifest_value support_archive)"
support_sha="$(manifest_value support_sha256)"
binary_archive="$(manifest_value binary_archive)"
binary_archive_sha="$(manifest_value binary_archive_sha256)"
binary_sha="$(manifest_value binary_sha256)"

[ "$manifest_release" = "$RELEASE" ] || fail "APK 升级版本清单不匹配"
[ "$manifest_version_code" = "$VERSION_CODE" ] || fail "APK versionCode 清单不匹配"
[ "$manifest_codex_version" = "$EXPECTED_CODEX_VERSION" ] || fail "Codex 版本清单不匹配"
[ "$manifest_target" = "$EXPECTED_TARGET" ] || fail "Codex 目标平台清单不匹配"
if [ "${CODEX_APK_UPGRADE_ALLOW_TEST_PAYLOAD:-0}" != "1" ]; then
  [ "$binary_archive_sha" = "$EXPECTED_ARCHIVE_SHA256" ] ||
    fail "Codex 归档 SHA 未匹配固定发布值"
  [ "$binary_sha" = "$EXPECTED_BINARY_SHA256" ] ||
    fail "Codex 二进制 SHA 未匹配固定发布值"
fi

copy_asset "$support_archive" "$WORK_ROOT/$support_archive"
copy_asset "$binary_archive" "$WORK_ROOT/$binary_archive"
verify_sha256 "$WORK_ROOT/$support_archive" "$support_sha"
verify_sha256 "$WORK_ROOT/$binary_archive" "$binary_archive_sha"

SUPPORT_DIR="$WORK_ROOT/support"
STAGE_BIN="$WORK_ROOT/install-bin"
STAGE_SCRIPTS="$WORK_ROOT/install-scripts"
mkdir -p "$SUPPORT_DIR" "$STAGE_BIN" "$STAGE_SCRIPTS"
tar -xzf "$WORK_ROOT/$support_archive" -C "$SUPPORT_DIR"
for required in \
  codex-apk-upgrade.sh \
  lib/codex-zh-common.sh \
  lib/codex-zh-config.sh \
  lib/codex-zh-local.sh \
  libexec/codex-config-engine.py \
  libexec/codex-config-select.py \
  libexec/codex-config-secret-read.py \
  libexec/codex-session-defaults.py \
  libexec/codex-tui-fold-bridge.py \
  libexec/codex-workspace-migrate.py \
  libexec/codex-runtime-session-import.py \
  data/openai-models.json
do
  [ -s "$SUPPORT_DIR/$required" ] || fail "支持脚本归档缺少：$required"
done

binary_extract="$WORK_ROOT/binary"
mkdir -p "$binary_extract"
tar -xzf "$WORK_ROOT/$binary_archive" -C "$binary_extract"
binary_source=""
for candidate in \
  "$binary_extract/codex-$EXPECTED_CODEX_VERSION-zh-$EXPECTED_TARGET" \
  "$binary_extract/codex" \
  "$binary_extract/codex-zh-bin"
do
  if [ -f "$candidate" ]; then
    binary_source="$candidate"
    break
  fi
done
[ -n "$binary_source" ] || fail "Codex 归档中没有目标二进制"
verify_sha256 "$binary_source" "$binary_sha"
cp "$binary_source" "$STAGE_BIN/codex-zh-bin"
chmod 755 "$STAGE_BIN/codex-zh-bin"

export CODEX_ZH_BIN_SHA256="$binary_sha"
export CODEX_ZH_RUNTIME_EPOCH="apk-$RELEASE"
# shellcheck disable=SC1090
. "$SUPPORT_DIR/lib/codex-zh-common.sh"
# shellcheck disable=SC1090
. "$SUPPORT_DIR/lib/codex-zh-config.sh"
# shellcheck disable=SC1090
. "$SUPPORT_DIR/lib/codex-zh-local.sh"
export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SUPPORT_DIR"
export CODEX_ZH_INSTALL_DIR="$STAGE_BIN"
export CODEX_ZH_SCRIPT_INSTALL_ROOT="$STAGE_SCRIPTS"
export CODEX_ZH_LAUNCHER_REAL_BIN="$INSTALL_DIR/codex-zh-bin"
export CODEX_ZH_LAUNCHER_BUILD_BIN="$STAGE_BIN/codex-zh-bin"
export CODEX_ZH_SKIP_PERSIST_PATH=1
codex_local_write_launcher
codex_local_install_support_scripts
STAGED_ENGINE="$STAGE_SCRIPTS/libexec/codex-config-engine.py"
[ -s "$STAGED_ENGINE" ] || fail "暂存配置引擎缺失"
WORKSPACE_MIGRATOR="$STAGE_SCRIPTS/libexec/codex-workspace-migrate.py"
[ -s "$WORKSPACE_MIGRATOR" ] || fail "暂存工作区迁移器缺失"
SESSION_DEFAULTS_ADAPTER="$STAGE_SCRIPTS/libexec/codex-session-defaults.py"
[ -s "$SESSION_DEFAULTS_ADAPTER" ] || fail "暂存会话默认值适配器缺失"

if [ -s "$JOURNAL" ]; then
  CONFIG_BACKUP="$(sed -n 's/^config_backup=//p' "$JOURNAL" | sed -n '1p')"
  WORKSPACE_BACKUP="$(sed -n 's/^workspace_backup=//p' "$JOURNAL" | sed -n '1p')"
  warn "检测到上次未完成的 APK 环境升级，先恢复再重试。"
  rollback_workspace
  rollback_config
  restore_managed
  rm -f "$JOURNAL"
  CONFIG_BACKUP=""
  WORKSPACE_BACKUP=""
fi

rm -rf "$MANAGED_BACKUP"
mkdir -p "$MANAGED_BACKUP/bin" "$INSTALL_DIR"
: > "$MANAGED_BACKUP/managed-files"
for staged in "$STAGE_BIN"/*; do
  [ -e "$staged" ] || [ -L "$staged" ] || continue
  name="$(basename "$staged")"
  printf '%s\n' "$name" >> "$MANAGED_BACKUP/managed-files"
  if [ -e "$INSTALL_DIR/$name" ] || [ -L "$INSTALL_DIR/$name" ]; then
    cp -a "$INSTALL_DIR/$name" "$MANAGED_BACKUP/bin/$name"
  fi
done
if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
  codex_write_system_path_profile "$INSTALL_DIR" ||
    warn "系统 PATH 托管片段修复失败；不影响本次会话。"
fi
if [ -d "$SCRIPT_ROOT" ]; then
  cp -a "$SCRIPT_ROOT" "$MANAGED_BACKUP/scripts"
fi

{
  printf 'release=%s\n' "$RELEASE"
  printf 'phase=prepared\n'
  printf 'manifest_sha256=%s\n' "$manifest_expected"
} > "$JOURNAL"

new_scripts="$SCRIPT_ROOT.apk-new.$$"
old_scripts="$SCRIPT_ROOT.apk-old.$$"
rm -rf "$new_scripts" "$old_scripts"
mkdir -p "$(dirname "$SCRIPT_ROOT")"
cp -a "$STAGE_SCRIPTS" "$new_scripts"
if [ -d "$SCRIPT_ROOT" ]; then
  mv "$SCRIPT_ROOT" "$old_scripts"
fi
if ! mv "$new_scripts" "$SCRIPT_ROOT"; then
  [ ! -d "$old_scripts" ] || mv "$old_scripts" "$SCRIPT_ROOT" 2>/dev/null || true
  fail "无法激活 APK 内置支持脚本"
fi
rm -rf "$old_scripts"

for staged in "$STAGE_BIN"/*; do
  [ -e "$staged" ] || [ -L "$staged" ] || continue
  name="$(basename "$staged")"
  temporary="$INSTALL_DIR/.apk-$RELEASE-$name.$$"
  rm -f "$temporary"
  cp -a "$staged" "$temporary"
  mv -f "$temporary" "$INSTALL_DIR/$name"
done

{
  printf 'release=%s\n' "$RELEASE"
  printf 'phase=managed-installed\n'
  printf 'manifest_sha256=%s\n' "$manifest_expected"
} > "$JOURNAL"

[ "${CODEX_APK_UPGRADE_FAILPOINT:-}" != "after-managed-install" ] ||
  fail "APK 升级故障注入：after-managed-install"

command -v python3 >/dev/null 2>&1 ||
  fail "缺少 python3，无法执行事务型配置迁移"
PYTHONNOUSERSITE=1 python3 "$STAGED_ENGINE" \
  --codex-home "$CONTROL_HOME" apk-upgrade --release "$RELEASE" \
  > "$RELEASE_STATE/config-upgrade.json"
CONFIG_BACKUP="$(
  python3 - "$RELEASE_STATE/config-upgrade.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("backup", ""))
PY
)"
[ -n "$CONFIG_BACKUP" ] || fail "配置升级未返回恢复点"

{
  printf 'release=%s\n' "$RELEASE"
  printf 'phase=config-upgraded\n'
  printf 'manifest_sha256=%s\n' "$manifest_expected"
  printf 'config_backup=%s\n' "$CONFIG_BACKUP"
} > "$JOURNAL"

[ "${CODEX_APK_UPGRADE_FAILPOINT:-}" != "after-config-upgrade" ] ||
  fail "APK 升级故障注入：after-config-upgrade"

PYTHONNOUSERSITE=1 python3 "$WORKSPACE_MIGRATOR" \
  --codex-home "$CONTROL_HOME" migrate \
  --from /root --to /root/workspace --release "$RELEASE" \
  --import-legacy-runtimes \
  > "$RELEASE_STATE/workspace-migration.json"
WORKSPACE_BACKUP="$(
  python3 - "$RELEASE_STATE/workspace-migration.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("backup", ""))
PY
)"

{
  printf 'release=%s\n' "$RELEASE"
  printf 'phase=workspace-migrated\n'
  printf 'manifest_sha256=%s\n' "$manifest_expected"
  printf 'config_backup=%s\n' "$CONFIG_BACKUP"
  printf 'workspace_backup=%s\n' "$WORKSPACE_BACKUP"
} > "$JOURNAL"

[ "${CODEX_APK_UPGRADE_FAILPOINT:-}" != "after-workspace-migration" ] ||
  fail "APK 升级故障注入：after-workspace-migration"

verify_sha256 "$INSTALL_DIR/codex-zh-bin" "$binary_sha"
sh -n "$INSTALL_DIR/codex"
sh -n "$SCRIPT_ROOT/lib/codex-zh-common.sh"
sh -n "$SCRIPT_ROOT/lib/codex-zh-config.sh"
sh -n "$SCRIPT_ROOT/lib/codex-zh-local.sh"
PYTHONNOUSERSITE=1 PYTHONPYCACHEPREFIX="$WORK_ROOT/pycache" python3 -m py_compile \
  "$SCRIPT_ROOT/libexec/codex-config-engine.py" \
  "$SCRIPT_ROOT/libexec/codex-config-select.py" \
  "$SCRIPT_ROOT/libexec/codex-config-secret-read.py" \
  "$SCRIPT_ROOT/libexec/codex-session-defaults.py" \
  "$SCRIPT_ROOT/libexec/codex-tui-fold-bridge.py" \
  "$SCRIPT_ROOT/libexec/codex-workspace-migrate.py" \
  "$SCRIPT_ROOT/libexec/codex-runtime-session-import.py"
refresh_existing_hook_blocks

version_raw="$("$INSTALL_DIR/codex-zh-bin" --version 2>/dev/null | sed -n '1p' || true)"
[ -n "$version_raw" ] || version_raw="codex"
build_key="$(
  codex_binary_seed_build_cache \
    "$INSTALL_DIR/codex-zh-bin" \
    "$version_raw" \
    "$binary_sha" \
    "apk-$RELEASE"
)" || fail "无法写入已校验 Codex 构建缓存"

PYTHONNOUSERSITE=1 python3 "$SCRIPT_ROOT/libexec/codex-config-engine.py" \
  --codex-home "$CONTROL_HOME" status > "$RELEASE_STATE/status.json"

python3 - "$CONTROL_HOME" "$RELEASE_STATE/status.json" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as handle:
    status = json.load(handle)
if status.get("schema_version") != 2:
    raise SystemExit("APK upgrade did not create schema V2")
if (home / "config.toml").is_file() and not status.get("active_profile_id"):
    raise SystemExit("root config exists but no active V2 profile was selected")
PY

active_profile="$(
  python3 - "$RELEASE_STATE/status.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("active_profile_id") or "")
PY
)"
if [ -n "$active_profile" ]; then
  PYTHONNOUSERSITE=1 python3 "$SCRIPT_ROOT/libexec/codex-config-engine.py" \
    --codex-home "$CONTROL_HOME" profile show "$active_profile" \
    > "$RELEASE_STATE/profile-before-session-defaults.json"
  profile_generation="$(
    codex_config_v2_json_value \
      "$RELEASE_STATE/profile-before-session-defaults.json" profile.generation
  )"
  baseline_model="$(
    codex_config_v2_json_value \
      "$RELEASE_STATE/profile-before-session-defaults.json" profile.model
  )"
  baseline_effort="$(
    codex_config_v2_json_value \
      "$RELEASE_STATE/profile-before-session-defaults.json" profile.reasoning_effort ||
      true
  )"
  model_provider_id="$(
    codex_config_v2_json_value \
      "$RELEASE_STATE/profile-before-session-defaults.json" profile.provider_id ||
      true
  )"
  profile_runtime="$(
    codex_config_v2_json_value \
      "$RELEASE_STATE/profile-before-session-defaults.json" profile.runtime_home
  )"
  CODEX_FOR_TUI_CONTROL_HOME="$CONTROL_HOME" \
  CODEX_FOR_TUI_PROFILE_ID="$active_profile" \
  CODEX_FOR_TUI_PROFILE_GENERATION="$profile_generation" \
  CODEX_FOR_TUI_BASELINE_MODEL="$baseline_model" \
  CODEX_FOR_TUI_BASELINE_REASONING_EFFORT="$baseline_effort" \
  CODEX_FOR_TUI_MODEL_PROVIDER_ID="$model_provider_id" \
  CODEX_HOME="$profile_runtime" \
    "$INSTALL_DIR/codex-session-defaults" migrate-latest \
      > "$RELEASE_STATE/session-defaults-migration.json" ||
    fail "无法迁移最近一次模型/思考等级选择"
  PYTHONNOUSERSITE=1 python3 "$SCRIPT_ROOT/libexec/codex-config-engine.py" \
    --codex-home "$CONTROL_HOME" profile launch \
    --sqlite-build-key "$build_key" > "$RELEASE_STATE/launch-check.json"
  python3 - "$CONTROL_HOME" "$RELEASE_STATE/launch-check.json" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1]).resolve()
with open(sys.argv[2], encoding="utf-8") as handle:
    value = json.load(handle)
runtime = Path(value["runtime_home"]).resolve()
sqlite = Path(value["sqlite_home"]).resolve()
if runtime == home:
    raise SystemExit("profile runtime reused control CODEX_HOME")
if runtime not in sqlite.parents or "sqlite-builds" not in sqlite.parts:
    raise SystemExit("SQLite home is not isolated under the profile runtime")
catalog = runtime / "model_catalog.json"
config = runtime / "config.toml"
if catalog.is_file():
    models = json.loads(catalog.read_text(encoding="utf-8")).get("models", [])
    for model in models:
        slug = model.get("slug")
        if isinstance(slug, str) and slug.startswith("codex-auto-"):
            if model.get("visibility") != "hide":
                raise SystemExit(f"auto model remained visible: {slug}")
if not config.is_file():
    raise SystemExit("profile runtime config was not materialized")
PY
fi

[ "${CODEX_APK_UPGRADE_FAILPOINT:-}" != "before-complete" ] ||
  fail "APK 升级故障注入：before-complete"

{
  printf 'release=%s\n' "$RELEASE"
  printf 'version_code=%s\n' "$VERSION_CODE"
  printf 'manifest_sha256=%s\n' "$manifest_expected"
  printf 'binary_sha256=%s\n' "$binary_sha"
  printf 'completed_at=%s\n' "$(date '+%s' 2>/dev/null || printf unknown)"
} > "$COMPLETE_MARKER.tmp.$$"
mv "$COMPLETE_MARKER.tmp.$$" "$COMPLETE_MARKER"
rm -f "$JOURNAL" "$RELEASE_STATE/failed"
# Drop staged archives after success so daily cold starts and disk stay light.
# Keep complete/status/refresh markers; only the multi-hundred-MB work tree goes.
rm -rf "$WORK_ROOT"
UPGRADE_ACTIVE=0

info "Codex for TUI $RELEASE 环境升级完成。"
best_effort_refresh
exit 0
