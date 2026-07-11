#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
BUILD_WORKFLOW="$ROOT_DIR/.github/workflows/build-codex-for-tui.yml"
CODEX_COMMON="$SCRIPT_DIR/lib/codex-zh-common.sh"
CODEX_SHA256SUMS="$SCRIPT_DIR/SHA256SUMS"
MODEL_CATALOG="$SCRIPT_DIR/data/openai-models.json"
MKSESSION="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MkSession.kt"
INIT_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/init.sh"
INIT_HOST_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/init-host.sh"
APP_BUILD_GRADLE="$ROOT_DIR/android-app/app/build.gradle.kts"
APP_MANIFEST="$ROOT_DIR/android-app/app/src/main/AndroidManifest.xml"
APK_UPGRADER="$SCRIPT_DIR/codex-apk-upgrade.sh"
APK_PAYLOAD_PREPARE="$ROOT_DIR/android-app/prepare-codex-apk-payload.sh"
APK_UPGRADE_SMOKE="$ROOT_DIR/tests/codex-for-tui-apk-upgrade-smoke.sh"
APK_PAYLOAD_INSPECT="$ROOT_DIR/tests/codex-for-tui-apk-payload-inspect.sh"
MODEL_PTY_SMOKE="$ROOT_DIR/tests/codex-for-tui-model-pty-smoke.py"
UPDATE_MANAGER="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/update/UpdateManager.kt"
RELEASE_KEYSTORE="$ROOT_DIR/android-app/app/codex-for-tui-2x-release.keystore"
LEGACY_DEBUG_KEYSTORE="$ROOT_DIR/android-app/app/testkey.keystore"
BOOTSTRAP="$SCRIPT_DIR/codex-for-tui-bootstrap.sh"
BOOTSTRAP_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh"
PREVIEW_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-preview"
PUSH_IMAGE_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-push-image"
PUSH_MEDIA_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-push-media"
BROWSER_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-browser"
PANEL_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-panel"
SESSION_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-session"
RTK_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-rtk"
CONTEXT_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-context"
DOCTOR_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-doctor"
CLEAN_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-clean"
OPS_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-ops"
OPS_LIB_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-ops-lib"
DEV_TRANSFER_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-dev-transfer"
BROWSER_SMOKE="$ROOT_DIR/tests/codex-for-tui-browser-smoke.sh"
DEVICE_SMOKE="$ROOT_DIR/tests/codex-for-tui-device-smoke.sh"
INSTALLED_DEVICE_SMOKE="$ROOT_DIR/tests/codex-for-tui-installed-device-smoke.sh"
OPS_SMOKE="$ROOT_DIR/tests/codex-for-tui-ops-smoke.sh"
DEV_TRANSFER_SMOKE="$ROOT_DIR/tests/codex-for-tui-dev-transfer-smoke.sh"
DEV_TRANSFER_SECURITY_SMOKE="$ROOT_DIR/tests/codex-for-tui-dev-transfer-security-smoke.sh"
CONFIG_SMOKE="$ROOT_DIR/tests/codex-for-tui-config-smoke.sh"
TERMINAL_TOP_BAR="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalTopBar.kt"
TERMINAL_SCREEN="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalScreen.kt"
MEDIA_PREVIEW_PANE="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MediaPreviewPane.kt"
MAIN_ACTIVITY="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/activities/terminal/MainActivity.kt"
BROWSER_PANEL_PANE="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/BrowserPanelPane.kt"
TERMINAL_BROWSER_SESSION="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalBrowserSession.kt"
TERMINAL_VIEW_MODEL="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalViewModel.kt"
TERMINAL_BACK_END="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalBackEnd.kt"
TERMINAL_VIEW_LAYOUT="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalViewLayout.kt"
SESSION_SERVICE="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/service/SessionService.kt"
ROOTFS_KT="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/Rootfs.kt"
SETUP_SCREEN="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/downloader/SetupScreen.kt"
RUN_COMMAND_SERVICE="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/service/RunCommandService.kt"
CRASH_HANDLER="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/crashhandler/CrashHandler.kt"
ALPINE_DOCUMENT_PROVIDER="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/AlpineDocumentProvider.kt"
BACKUP_RULES="$ROOT_DIR/android-app/core/main/src/main/res/xml/backup_rules.xml"
DATA_EXTRACTION_RULES="$ROOT_DIR/android-app/core/main/src/main/res/xml/data_extraction_rules.xml"
FILE_PATHS_XML="$ROOT_DIR/android-app/core/main/src/main/res/xml/file_paths.xml"
NETWORK_SECURITY_CONFIG="$ROOT_DIR/android-app/core/main/src/main/res/xml/network_security_config.xml"

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

assert_contains() {
  haystack="$1"
  needle="$2"
  label="$3"
  printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1 || fail "$label missing: $needle"
}

assert_not_contains() {
  haystack="$1"
  needle="$2"
  label="$3"
  if printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    fail "$label should not contain: $needle"
  fi
}

assert_nonempty_file() {
  file="$1"
  [ -s "$file" ] || fail "expected non-empty file: $file"
}

assert_file_order() {
  file="$1"
  first="$2"
  second="$3"
  first_line="$(grep -n -F -m 1 -- "$first" "$file" | cut -d: -f1)"
  second_line="$(grep -n -F -m 1 -- "$second" "$file" | cut -d: -f1)"
  [ -n "$first_line" ] && [ -n "$second_line" ] ||
    fail "could not compare pattern order in $file"
  [ "$first_line" -lt "$second_line" ] ||
    fail "expected '$first' before '$second' in $file"
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
  assert_file_contains "$MKSESSION" 'fun sanitizeSessionId'
  assert_file_contains "$MKSESSION" 'PROOT_TMP_DIR=${localDir().child("proot-tmp").child(sanitizeSessionId(sessionId)'
  assert_file_contains "$SESSION_SERVICE" 'cleanupSessionTempDir(id)'
  assert_file_contains "$SESSION_SERVICE" 'terminateAllSessions(updateNotification = false)'
  assert_file_contains "$INIT_ASSET" 'export HOME="${HOME:-/root}"'
  assert_file_contains "$INIT_ASSET" 'export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"'
}

test_android_lifecycle_rootfs_guards() {
  sh -n "$INIT_HOST_ASSET" || fail "init-host.sh shell syntax failed"
  assert_file_contains "$INIT_HOST_ASSET" 'ROOTFS_LOCK='
  assert_file_contains "$INIT_HOST_ASSET" 'ROOTFS_READY_MARKER=".codex-rootfs-ready"'
  assert_file_contains "$INIT_HOST_ASSET" 'ROOTFS_EXTRACT_DIR="$PREFIX/local/alpine.extracting.$$"'
  assert_file_contains "$INIT_HOST_ASSET" 'Unable to activate new Alpine rootfs'
  assert_file_contains "$ROOTFS_KT" 'ARCHIVE_READY_MARKER'
  assert_file_contains "$ROOTFS_KT" 'withInstallLock'
  assert_file_contains "$ROOTFS_KT" 'output.fd.sync()'
  assert_file_contains "$SETUP_SCREEN" 'Rootfs.prepareArchiveFromAsset(context, assetName)'
  assert_file_contains "$RUN_COMMAND_SERVICE" 'return START_NOT_STICKY'
  assert_file_not_contains "$RUN_COMMAND_SERVICE" 'TODO()'
  assert_file_contains "$CRASH_HANDLER" 'fun install()'
  assert_file_contains "$CRASH_HANDLER" 'previousHandler'
  assert_file_not_contains "$CRASH_HANDLER" 'Looper.loop()'
  assert_file_contains "$TERMINAL_BACK_END" 'WeakReference(terminal)'
  assert_file_contains "$TERMINAL_BACK_END" 'WeakReference(activity)'
  assert_file_not_contains "$TERMINAL_BACK_END" 'private val terminal: TerminalView'
  assert_file_not_contains "$TERMINAL_BACK_END" 'private val activity: MainActivity'
}

test_bootstrap_asset_is_synced() {
  cmp "$BOOTSTRAP" "$BOOTSTRAP_ASSET" >/dev/null 2>&1 || fail "bootstrap source and APK asset differ"
}

test_apk_upgrade_guards() {
  for script in "$APK_UPGRADER" "$APK_PAYLOAD_PREPARE" "$APK_UPGRADE_SMOKE" "$APK_PAYLOAD_INSPECT"; do
    assert_nonempty_file "$script"
    sh -n "$script" || fail "$(basename "$script") shell syntax failed"
  done
  assert_nonempty_file "$MODEL_PTY_SMOKE"
  python3 -m py_compile "$MODEL_PTY_SMOKE" || fail "model PTY smoke Python syntax failed"

  assert_file_contains "$APK_UPGRADER" 'RELEASE="2.4.10"'
  assert_file_contains "$APK_UPGRADER" 'VERSION_CODE="65"'
  assert_file_contains "$APK_UPGRADER" 'EXPECTED_ARCHIVE_SHA256="1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61"'
  assert_file_contains "$APK_UPGRADER" 'EXPECTED_BINARY_SHA256="0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767"'
  assert_file_contains "$APK_UPGRADER" 'LOCK_DIR="$STATE_ROOT/apk-upgrade.lock"'
  assert_file_contains "$APK_UPGRADER" 'process_start_token'
  assert_file_contains "$APK_UPGRADER" '"$LOCK_DIR/start"'
  assert_file_contains "$APK_UPGRADER" '[ "$waited" -ge 2 ]'
  assert_file_contains "$APK_UPGRADER" 'JOURNAL="$RELEASE_STATE/transaction"'
  assert_file_contains "$APK_UPGRADER" 'rollback_config'
  assert_file_contains "$APK_UPGRADER" 'restore_managed'
  assert_file_contains "$APK_UPGRADER" 'apk-upgrade --release "$RELEASE"'
  assert_file_contains "$APK_UPGRADER" 'apk-rollback --backup "$CONFIG_BACKUP"'
  assert_file_contains "$APK_UPGRADER" 'profile launch'
  assert_file_contains "$APK_UPGRADER" 'runtime == home'
  assert_file_contains "$APK_UPGRADER" 'slug.startswith("codex-auto-")'
  assert_file_contains "$APK_UPGRADER" 'best_effort_refresh'
  assert_file_contains "$APK_UPGRADER" '第三方模型目录联网刷新失败，已保留离线重建结果。'

  assert_file_contains "$APK_PAYLOAD_PREPARE" 'RELEASE="2.4.10"'
  assert_file_contains "$APK_PAYLOAD_PREPARE" 'VERSION_CODE="65"'
  assert_file_contains "$APK_PAYLOAD_PREPARE" "tar \\"
  assert_file_contains "$APK_PAYLOAD_PREPARE" "--sort=name"
  assert_file_contains "$APK_PAYLOAD_PREPARE" "--mtime='UTC 1970-01-01'"
  assert_file_contains "$APK_PAYLOAD_PREPARE" 'support_archive="codex-support-$RELEASE.tgz"'
  assert_file_contains "$APK_PAYLOAD_PREPARE" 'binary_archive="codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}.tgz"'
  assert_file_contains "$APK_PAYLOAD_PREPARE" 'binary_archive_sha256=$archive_sha'
  assert_file_contains "$APK_PAYLOAD_PREPARE" 'binary_sha256=$binary_sha'

  assert_file_contains "$INIT_ASSET" 'APK 环境升级入口缺失，已阻止 Codex 启动。'
  assert_file_contains "$INIT_ASSET" '--prepare-apk-upgrade-deps'
  assert_file_contains "$INIT_ASSET" '无法准备 APK 环境升级所需的 python3'
  assert_file_contains "$INIT_ASSET" 'HOME=/root CODEX_HOME=/root/.codex sh "$apk_upgrade"'
  assert_file_contains "$INIT_ASSET" 'APK 环境升级未完成，已回滚并阻止 Codex 启动'
  assert_file_order "$INIT_ASSET" '--prepare-apk-upgrade-deps' 'sh "$apk_upgrade"'
  assert_file_order "$INIT_ASSET" 'sh "$apk_upgrade"' 'sh "$bootstrap" ||'
  assert_file_contains "$MKSESSION" '"codex-apk-upgrade.sh" to "codex-apk-upgrade"'
  assert_file_contains "$UPDATE_MANAGER" '"codex-apk-upgrade.sh" to "codex-apk-upgrade"'
  assert_file_contains "$BOOTSTRAP" 'prepare_apk_upgrade_deps'
  assert_file_contains "$BOOTSTRAP" '"$apk_command" add --no-cache python3'
  assert_file_contains "$BOOTSTRAP" 'CODEX_FOR_TUI_DEPS_MAX_ATTEMPTS'
  assert_file_contains "$BOOTSTRAP" '下次打开 App 会自动重试'
  # 2.4.5+: shell-first default, no auto exec codex
  assert_file_contains "$BOOTSTRAP" 'auto_start="${CODEX_FOR_TUI_AUTO_START:-0}"'
  assert_file_contains "$BOOTSTRAP" 'print_ready_shell_hint'
  assert_file_contains "$BOOTSTRAP" 'CODEX_ZH_SKIP_RUN=1'
  assert_file_not_contains "$BOOTSTRAP" 'Codex 已安装，直接启动。'
  assert_file_not_contains "$BOOTSTRAP" 'CODEX_FOR_TUI_AUTO_START:-1'
  # 2.4.6+/2.4.7: ready guide then pure interactive shell handoff
  assert_file_contains "$BOOTSTRAP" '常用命令'
  assert_file_contains "$BOOTSTRAP" '启动 Codex TUI'
  assert_file_contains "$BOOTSTRAP" '管理站点、模型与压缩策略'
  assert_file_contains "$BOOTSTRAP" '引导结束，进入 shell。'
  assert_file_contains "$BOOTSTRAP_ASSET" '引导结束，进入 shell。'
  assert_file_contains "$INIT_ASSET" 'CODEX_FOR_TUI_WORKSPACE'
  assert_file_contains "$INIT_ASSET" 'CODEX_FOR_TUI_AUTO_START="${CODEX_FOR_TUI_AUTO_START:-0}"'
  # 2.4.6+/2.4.7: interactive shell + tty hygiene for live echo
  assert_file_contains "$INIT_ASSET" 'enter_interactive_shell'
  assert_file_contains "$INIT_ASSET" 'stty sane'
  assert_file_contains "$INIT_ASSET" 'exec /bin/ash -i'
  assert_file_contains "$INIT_ASSET" 'export ENV='
  # Bare non-interactive shell entry must not remain.
  if grep -nE 'exec /bin/ash([[:space:]]|$)' "$INIT_ASSET" | grep -v 'ash -i' >/dev/null 2>&1; then
    fail "init.sh still has non-interactive exec /bin/ash"
  fi
  # 2.4.7: file tray multi-select + short display names + top send
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MediaPreviewPane.kt" 'onSendManyToAi'
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MediaPreviewPane.kt" 'shortPreviewDisplayName'
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MediaPreviewPane.kt" '发送($selectedCount)'
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/activities/terminal/MainActivity.kt" 'fun sendPreviewsToAi'
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/activities/terminal/MainActivity.kt" '"$stamp-$kindToken.$ext"' 
  assert_file_contains "$INIT_HOST_ASSET" 'CODEX_FOR_TUI_FILTER_PROOT_WARNINGS'
  assert_file_contains "$INIT_HOST_ASSET" "proot warning: can't sanitize binding"
  assert_file_contains "$INIT_HOST_ASSET" 'proot warning: ptrace('
  assert_file_contains "$INIT_HOST_ASSET" 'Please set PROOT_TMP_DIR'
  # 2.4.8: pure shell lands at $HOME; workspace only for codex launcher
  assert_file_contains "$INIT_ASSET" 'Pure shell home'
  assert_file_contains "$INIT_ASSET" 'cd "$HOME"'
  assert_file_contains "$MKSESSION" 'proot-tmp'
  assert_file_contains "$MKSESSION" 'CODEX_FOR_TUI_AUTO_START='
  assert_file_contains "$MKSESSION" 'CODEX_FOR_TUI_WORKSPACE=/root/workspace'
  assert_file_contains "$MKSESSION" 'Settings.auto_start_codex'
  # 2.4.9: never-blank startup + skip rewriting multi-MB managed scripts every session
  assert_file_contains "$INIT_HOST_ASSET" 'Codex for TUI：正在启动'
  assert_file_contains "$INIT_ASSET" 'Codex for TUI：环境已就绪，正在初始化'
  assert_file_contains "$INIT_ASSET" '正在进入交互 shell'
  # 2.4.10: guide ends into live shell without ^C — reconnect stderr + byte-wise proot filter
  assert_file_contains "$INIT_ASSET" 'exec 2>&1'
  assert_file_contains "$INIT_HOST_ASSET" 'read -r -n 1'
  assert_file_contains "$INIT_HOST_ASSET" 'could_become_proot_noise'
  assert_file_not_contains "$INIT_HOST_ASSET" 'while IFS= read -r line || [ -n "$line" ]; do'
  assert_file_contains "$INIT_ASSET" 'sanitize_profile_d'
  assert_file_contains "$MKSESSION" 'MANAGED_SCRIPTS_STAMP'
  assert_file_contains "$MKSESSION" 'managedScriptsStampValue'
  assert_file_contains "$MKSESSION" 'packageManager.getPackageInfo'
  assert_file_contains "$UPDATE_MANAGER" 'packageManager.getPackageInfo'
  # library module has no application BuildConfig.VERSION_*; must not regress
  if grep -n 'BuildConfig.VERSION_CODE\|BuildConfig.VERSION_NAME' "$MKSESSION" "$UPDATE_MANAGER" >/dev/null 2>&1; then
    fail "MkSession/UpdateManager must not use library BuildConfig.VERSION_* (unresolved in :core:main)"
  fi
  assert_file_contains "$MKSESSION" 'openFd'
  assert_file_contains "$APK_UPGRADER" 'rm -rf "$WORK_ROOT"'
  assert_file_contains "$UPDATE_MANAGER" 'update-manager-stamp'
  # 2.4.6: DEFAULT input uses TYPE_NULL (not VISIBLE_PASSWORD)
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalBackEnd.kt"     'Settings.input_mode == InputMode.VISIBLE_PASSWORD'
  assert_file_not_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalBackEnd.kt"     'Settings.input_mode != 1'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'CODEX_FOR_TUI_WORKSPACE'
  assert_file_contains "$APK_UPGRADER" 'Daily cold start: upgrade already complete'
  assert_file_contains "$ROOT_DIR/tests/codex-for-tui-installer-smoke.sh" \
    'test_bootstrap_prepares_python_dependency_with_retry'
  assert_file_contains "$ROOT_DIR/tests/codex-for-tui-installer-smoke.sh" \
    'test_bootstrap_dependency_failure_retries_on_next_start'
  assert_file_contains "$ROOT_DIR/tests/codex-for-tui-installer-smoke.sh" \
    'test_bootstrap_dependency_cancel_does_not_install'

  assert_file_contains "$APP_BUILD_GRADLE" 'val verifyCodexUpgradePayload by tasks.registering'
  assert_file_contains "$APP_BUILD_GRADLE" 'release"] != "2.4.10"'
  assert_file_contains "$APP_BUILD_GRADLE" 'version_code"] != "65"'
  assert_file_contains "$APP_BUILD_GRADLE" 'Codex APK manifest SHA256 mismatch'
  assert_file_contains "$APP_BUILD_GRADLE" 'AAPT strips that asset suffix; use .tgz'
  assert_file_contains "$APP_BUILD_GRADLE" 'dependsOn(verifyCodexUpgradePayload)'
  assert_file_contains "$CODEX_COMMON" ': "${CODEX_ZH_RUNTIME_EPOCH:=apk-2.4.10}"'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'epoch="${CODEX_ZH_RUNTIME_EPOCH:-apk-2.4.10}"'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" '配置引擎未返回独立运行目录；未启动 Codex。'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'config-profiles/current'
  assert_file_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'if model.get("tool_mode") == "code_mode_only":'
  assert_file_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'model["tool_mode"] = None'
  assert_file_not_contains "$MODEL_CATALOG" '"tool_mode": "code_mode_only"'
  assert_file_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'legacy_profile_already_imported'

  assert_file_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'seed_runtime_state('
  assert_file_not_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'runtime_home=legacy_dir'

  assert_file_contains "$APK_UPGRADE_SMOKE" 'after-config-upgrade'
  assert_file_contains "$APK_UPGRADE_SMOKE" 'before-complete'
  assert_file_contains "$APK_UPGRADE_SMOKE" 'test_v1_runtime_is_unchanged_after_late_rollback'
  assert_file_contains "$APK_UPGRADE_SMOKE" 'test_stale_empty_lock_is_recovered'
  assert_file_contains "$APK_UPGRADE_SMOKE" 'test_concurrent_upgrade_is_serialized'
  assert_file_contains "$APK_PAYLOAD_INSPECT" 'assets/codex-upgrade/manifest.properties'
  assert_file_contains "$APK_PAYLOAD_INSPECT" 'AAPT-unsafe .gz asset suffix'
  assert_file_contains "$APK_PAYLOAD_INSPECT" 'APK is too small to contain the fixed offline payload'
  assert_file_contains "$MODEL_PTY_SMOKE" 'Paste-burst protection must expire before Enter submits the command.'
  assert_file_contains "$MODEL_PTY_SMOKE" '选择模型和推理等级'
  assert_file_contains "$MODEL_PTY_SMOKE" '("低（默认）", "中", "高", "极高", "Max", "Ultra")'
}

test_debug_build_uses_test_package_name() {
  assert_file_contains "$APP_BUILD_GRADLE" 'applicationIdSuffix = ".test"'
  assert_file_contains "$APP_BUILD_GRADLE" 'versionNameSuffix = "-TEST"'
  assert_file_contains "$APP_BUILD_GRADLE" 'Codex for TUI Test'
  assert_file_contains "$APP_BUILD_GRADLE" 'versionCode = 65'
  assert_file_contains "$APP_BUILD_GRADLE" 'versionName = "2.4.10"'
}

test_release_workflow_signature_gate() {
  assert_file_contains "$BUILD_WORKFLOW" '- "release/codex-for-tui-*"'
  assert_file_contains "$BUILD_WORKFLOW" 'CODEX_TUI_RELEASE_CERT_SHA256: a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc'
  assert_file_contains "$BUILD_WORKFLOW" 'CODEX_TUI_EXPECTED_PACKAGE_NAME: com.gzy3894.codexfortui'
  assert_file_contains "$BUILD_WORKFLOW" 'CODEX_TUI_EXPECTED_VERSION_CODE: "65"'
  assert_file_contains "$BUILD_WORKFLOW" 'CODEX_TUI_EXPECTED_VERSION_NAME: 2.4.10'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Verify release version inputs'
  assert_file_contains "$BUILD_WORKFLOW" 'GITHUB_REF_NAME#codex-for-tui-v'
  assert_file_contains "$BUILD_WORKFLOW" 'Tag/versionName mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'Gradle versionCode mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'Gradle applicationId mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Prepare release signing key'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Config manager smoke tests'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-config-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-config-v2-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-config-v2-ui-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-apk-upgrade-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Dev transfer smoke tests'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-dev-transfer-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-dev-transfer-security-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'Missing required GitHub secret'
  assert_file_contains "$BUILD_WORKFLOW" 'Release signing secrets are required; repository/test keystore fallback is forbidden.'
  assert_file_contains "$BUILD_WORKFLOW" 'base64 --decode > /tmp/xed.keystore'
  assert_file_contains "$BUILD_WORKFLOW" 'printf '\''storeFile=%s\n'\'' "/tmp/xed.keystore"'
  assert_file_contains "$BUILD_WORKFLOW" 'Using configured GitHub Secrets release signing key.'
  assert_file_not_contains "$BUILD_WORKFLOW" 'test -s app/codex-for-tui-2x-release.keystore'
  assert_file_not_contains "$BUILD_WORKFLOW" 'Using repository 2.x release keystore'
  assert_file_not_contains "$BUILD_WORKFLOW" 'cp app/testkey.keystore /tmp/xed.keystore'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Verify release APKs'
  assert_file_contains "$BUILD_WORKFLOW" 'mapfile -t apks'
  assert_file_contains "$BUILD_WORKFLOW" 'for apk in "${apks[@]}"; do'
  assert_file_contains "$BUILD_WORKFLOW" '"$apksigner" verify --print-certs "$apk"'
  assert_file_contains "$BUILD_WORKFLOW" '"$aapt" dump badging "$apk"'
  assert_file_contains "$BUILD_WORKFLOW" 'Signer #1 certificate SHA-256 digest:'
  assert_file_contains "$BUILD_WORKFLOW" 'Release APK signing certificate mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'Release APK packageName mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'Release APK versionCode mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'Release APK versionName mismatch'
  assert_file_contains "$BUILD_WORKFLOW" "grep -qx 'application-debuggable'"
  assert_file_contains "$BUILD_WORKFLOW" 'Release APK must not be debuggable'
  assert_file_contains "$BUILD_WORKFLOW" 'debuggable=false'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Generate release SHA256SUMS'
  assert_file_contains "$BUILD_WORKFLOW" 'sha256sum *.apk > SHA256SUMS'
  assert_file_contains "$BUILD_WORKFLOW" 'android-app/app/build/outputs/apk/release/SHA256SUMS'
  assert_file_contains "$BUILD_WORKFLOW" 'softprops/action-gh-release@v2'
  assert_file_contains "$BUILD_WORKFLOW" 'body_path: docs/codex-for-tui-2.4.10-release-notes.md'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Publish verified GitHub release'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Download verified release assets'
  assert_file_order "$BUILD_WORKFLOW" 'name: Promote verified tag to installer channel' 'name: Publish verified GitHub release'
  assert_file_contains "$BUILD_WORKFLOW" 'artifact_name=codex-for-tui-release-apk'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Build RTK aarch64 musl'
  assert_file_contains "$BUILD_WORKFLOW" 'repository: rtk-ai/rtk'
  assert_file_contains "$BUILD_WORKFLOW" 'ref: v0.43.0'
  assert_file_contains "$BUILD_WORKFLOW" 'cross build --release --target aarch64-unknown-linux-musl'
  assert_file_contains "$BUILD_WORKFLOW" 'qemu-aarch64 /tmp/rtk --version'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Verify fixed Codex under qemu'
  assert_file_contains "$BUILD_WORKFLOW" '. android-arm64-musl/lib/codex-zh-common.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'archive_url="${CODEX_ZH_ARCHIVE_URL:-$CODEX_ZH_BINARY_BASE_URL/$CODEX_ZH_ARCHIVE}"'
  assert_file_contains "$BUILD_WORKFLOW" 'codex_verify_sha256 "$archive" "$CODEX_ZH_ARCHIVE_SHA256"'
  assert_file_contains "$BUILD_WORKFLOW" 'codex_verify_sha256 "$codex_bin" "$CODEX_ZH_BIN_SHA256"'
  assert_file_contains "$BUILD_WORKFLOW" 'exec qemu-aarch64 "$CODEX_QEMU_BINARY" "$@"'
  assert_file_contains "$BUILD_WORKFLOW" 'CODEX_BIN="$wrapper"'
  assert_file_contains "$BUILD_WORKFLOW" 'sh tests/codex-for-tui-config-v2-codex-parser-smoke.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'python3 tests/codex-for-tui-model-pty-smoke.py'
  assert_file_contains "$BUILD_WORKFLOW" '--qemu "$(command -v qemu-aarch64)"'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Upload verified Codex archive'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Prepare offline Codex upgrade payload'
  assert_file_contains "$BUILD_WORKFLOW" './prepare-codex-apk-payload.sh'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Verify test APK offline payload'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Verify release APK offline payload'
  assert_file_contains "$BUILD_WORKFLOW" '../tests/codex-for-tui-apk-payload-inspect.sh "$apk"'
  assert_file_not_contains "$BUILD_WORKFLOW" '0.142.4'
  assert_file_contains "$CODEX_COMMON" ': "${CODEX_ZH_VERSION:=0.144.1}"'
  assert_file_contains "$CODEX_COMMON" 'releases/download/v0.144.1-zh.1'
  assert_file_contains "$CODEX_COMMON" 'CODEX_ZH_ARCHIVE_SHA256="${CODEX_ZH_ARCHIVE_SHA256:-1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61}"'
  assert_file_contains "$CODEX_COMMON" 'CODEX_ZH_BIN_SHA256="${CODEX_ZH_BIN_SHA256:-0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767}"'
  assert_file_not_contains "$CODEX_COMMON" '0.142.4'
  assert_file_contains "$CODEX_SHA256SUMS" '1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61  codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz'
  assert_file_contains "$CODEX_SHA256SUMS" '0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767  codex-0.144.1-zh-aarch64-unknown-linux-musl'
  model_catalog_sha="$(sha256sum "$MODEL_CATALOG" | awk '{print $1}')"
  [ "$model_catalog_sha" = "6725a4e7588c7d41e16192f879a63d814bb1cda39d94c3c76847244ffd983f3e" ] ||
    fail "unexpected localized model catalog SHA256: $model_catalog_sha"
  assert_file_contains "$BUILD_WORKFLOW" 'cp /tmp/codex-for-tui-rtk/rtk core/main/src/main/assets/rtk'
  assert_file_contains "$BUILD_WORKFLOW" 'promote-installer-channel:'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Promote verified tag to installer channel'
  assert_file_contains "$BUILD_WORKFLOW" '- android-release-build'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Fast-forward installer channel'
  assert_file_contains "$BUILD_WORKFLOW" 'tag_commit="$(git rev-list -n 1 "$GITHUB_REF")"'
  assert_file_contains "$BUILD_WORKFLOW" 'git merge-base --is-ancestor "$channel_commit" "$tag_commit"'
  assert_file_contains "$BUILD_WORKFLOW" 'git push origin "$tag_commit:$channel_ref"'
  assert_file_not_contains "$BUILD_WORKFLOW" 'git push --force'
  assert_file_not_contains "$BUILD_WORKFLOW" 'git push -f'
  assert_file_not_contains "$BUILD_WORKFLOW" 'git push origin "+'
  assert_file_not_contains "$BUILD_WORKFLOW" 'codex-for-tui-unsigned-or-test-signed-release-apk'
  [ ! -e "$RELEASE_KEYSTORE" ] || fail "repository release keystore must not be committed: $RELEASE_KEYSTORE"
  [ ! -e "$LEGACY_DEBUG_KEYSTORE" ] || fail "legacy debug-named release key should be moved: $LEGACY_DEBUG_KEYSTORE"
  assert_file_contains "$APP_BUILD_GRADLE" 'fun requireSigningProperty(properties: Properties, name: String): String'
  assert_file_contains "$APP_BUILD_GRADLE" 'ANDROID_RELEASE_SIGNING_PROPERTIES'
  assert_file_contains "$APP_BUILD_GRADLE" '"/tmp/signing.properties"'
  assert_file_contains "$APP_BUILD_GRADLE" 'storeFile = File(requireSigningProperty(properties, "storeFile"))'
  assert_file_contains "$APP_BUILD_GRADLE" 'keyAlias = requireSigningProperty(properties, "keyAlias")'
  assert_file_contains "$APP_BUILD_GRADLE" 'Release signing is required; refusing to build an unsigned, debug-signed, or repository-signed APK.'
  assert_file_contains "$APP_BUILD_GRADLE" 'Release signing keystore must be supplied outside the repository; repository keystore/testkey fallback is disabled.'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'repositoryReleaseKeystore'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'codex-for-tui-2x-release.keystore'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'storeFile = repositoryReleaseKeystore'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'keyAlias = "testkey"'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'keyPassword = "testkey"'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'storePassword = "testkey"'
  assert_file_contains "$APP_BUILD_GRADLE" 'signingConfig = signingConfigs.getByName("release")'
  assert_file_contains "$APP_BUILD_GRADLE" 'tasks.matching { it.name == "validateSigningRelease" }'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'signingConfig = signingConfigs.getByName("debug")'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'signingConfig = if (signingConfigs.getByName("release").storeFile?.exists() == true)'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'getByName("debug") {'
  assert_file_not_contains "$APP_BUILD_GRADLE" 'testkey.keystore'
}

test_android_security_guards() {
  assert_file_contains "$APP_MANIFEST" 'android:allowBackup="false"'
  assert_file_contains "$APP_MANIFEST" 'android:networkSecurityConfig="@xml/network_security_config"'
  assert_file_contains "$NETWORK_SECURITY_CONFIG" '<base-config cleartextTrafficPermitted="false"'
  assert_file_contains "$NETWORK_SECURITY_CONFIG" '<domain-config cleartextTrafficPermitted="true"'
  assert_file_contains "$NETWORK_SECURITY_CONFIG" '<domain>localhost</domain>'
  assert_file_contains "$NETWORK_SECURITY_CONFIG" '<domain>127.0.0.1</domain>'
  assert_file_contains "$FILE_PATHS_XML" 'name="media_preview_share"'
  assert_file_contains "$FILE_PATHS_XML" 'path="media-preview-share/"'
  assert_file_not_contains "$FILE_PATHS_XML" '<external-path'
  assert_file_not_contains "$FILE_PATHS_XML" 'path="."'
  assert_file_contains "$BACKUP_RULES" '<exclude domain="file" path="."'
  assert_file_contains "$BACKUP_RULES" '<exclude domain="sharedpref" path="."'
  assert_file_contains "$DATA_EXTRACTION_RULES" '<exclude domain="file" path="."'
  assert_file_contains "$DATA_EXTRACTION_RULES" '<exclude domain="sharedpref" path="."'
  assert_file_contains "$ALPINE_DOCUMENT_PROVIDER" 'private fun getDocIdForFile(file: File): String'
  assert_file_contains "$ALPINE_DOCUMENT_PROVIDER" 'private fun getFileForDocId(docId: String): File'
  assert_file_contains "$ALPINE_DOCUMENT_PROVIDER" 'private fun isFileInsideBase(file: File): Boolean'
  assert_file_contains "$ALPINE_DOCUMENT_PROVIDER" 'private fun isSameOrDescendant(parent: File, child: File): Boolean'
  assert_file_contains "$ALPINE_DOCUMENT_PROVIDER" 'Document path is outside the Alpine home'
}

test_terminal_performance_guards() {
  assert_file_contains "$TERMINAL_BACK_END" 'object TerminalRenderPerformanceMetrics'
  assert_file_contains "$TERMINAL_BACK_END" 'private val screenUpdateRunnable'
  assert_file_contains "$TERMINAL_BACK_END" 'postOnAnimationDelayed'
  assert_file_contains "$TERMINAL_BACK_END" 'changedSession != terminal.currentSession'
  assert_file_contains "$TERMINAL_BACK_END" 'TerminalRenderPerformanceMetrics.recordRequest'
  assert_file_contains "$TERMINAL_BACK_END" 'TerminalRenderPerformanceMetrics.recordFrame'
  assert_file_not_contains "$TERMINAL_BACK_END" 'override fun onTextChanged(changedSession: TerminalSession) { terminal.onScreenUpdated() }'
  assert_file_not_contains "$TERMINAL_VIEW_LAYOUT" 'view.onScreenUpdated()'
  assert_file_contains "$TERMINAL_VIEW_LAYOUT" 'postInvalidateOnAnimation'
  assert_file_contains "$MAIN_ACTIVITY" 'FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO'
  assert_file_contains "$MAIN_ACTIVITY" 'private const val BRIDGE_FALLBACK_POLL_MS = 1500L'
  assert_file_contains "$MAIN_ACTIVITY" 'pollBrowserRequestLocked'
  assert_file_contains "$MAIN_ACTIVITY" 'private fun sanitizeBrowserResult'
  assert_file_contains "$MAIN_ACTIVITY" 'val persistedResult = sanitizeBrowserResult(result)'
  assert_file_contains "$MAIN_ACTIVITY" 'browserDir.child("result.json").writeText(persistedResult.toString(2))'
  assert_file_contains "$MAIN_ACTIVITY" 'requestResultsDir.child("$safeId.json").writeText(persistedResult.toString(2))'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'currentUrl = redactSensitiveUrl(auth?.url ?: active?.currentUrl.orEmpty())'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'target = redactSensitiveUrl(it.target)'
  assert_file_not_contains "$TERMINAL_BROWSER_SESSION" 'currentUrl = auth?.url ?: active?.currentUrl.orEmpty()'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'clearCompletedUserTasksForPageAction(action)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'window.eval(source)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'new Function(source)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'val alreadyLoaded = tab.currentUrl.isNotBlank()'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'if (alreadyLoaded) {'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'private fun canonicalLoadUrl'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'uri.encodedPath.orEmpty().ifBlank { "/" }'
  assert_file_contains "$BROWSER_SMOKE" 'opening the already loaded URL should complete'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'attachOffscreenCaptureHost'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'CapturableWebView'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'WebView.enableSlowWholeDocumentDraw()'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'root.addView(host, 0, ViewGroup.LayoutParams(width, height))'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'drawWebViewContentBitmap'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'awaitChoreographerFrame'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'drawPageTextFallbackBitmap'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'document.body && document.body.innerText'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'captureWebViewPictureBitmap'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'setLayerType(View.LAYER_TYPE_SOFTWARE, null)'
  assert_file_not_contains "$TERMINAL_BROWSER_SESSION" 'alpha = 0.01f'
  assert_file_not_contains "$TERMINAL_BROWSER_SESSION" 'translationX = (appContext.resources.displayMetrics.widthPixels + 64).toFloat()'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'postVisualStateCallback'
  assert_file_contains "$MAIN_ACTIVITY" 'override fun onDestroy()'
  assert_file_contains "$MAIN_ACTIVITY" 'pollSessionFoldRequestLocked'
  if awk '
    /override fun onStop\(\)/ { in_on_stop=1 }
    in_on_stop && /override fun onDestroy\(\)/ { in_on_stop=0 }
    in_on_stop && /override fun onPause\(\)/ { in_on_stop=0 }
    in_on_stop && (/mediaPreviewJob\?\.cancel\(\)/ || /browserBridgeJob\?\.cancel\(\)/ || /sessionFoldJob\?\.cancel\(\)/ || /stopBridgeObservers\(\)/) { bad=1 }
    END { exit bad ? 0 : 1 }
  ' "$MAIN_ACTIVITY"; then
    fail "MainActivity.onStop must not stop bridge jobs/observers; Custom Tabs background flows still need bridge consumption"
  fi
  assert_file_contains "$MAIN_ACTIVITY" 'localDir().child("perf").apply { mkdirs() }.child("terminal.status")'
  assert_file_contains "$MAIN_ACTIVITY" 'render_requests='
  assert_file_contains "$MAIN_ACTIVITY" 'render_frames='
  assert_file_contains "$MAIN_ACTIVITY" 'coalesced_requests='
  assert_file_contains "$MAIN_ACTIVITY" 'burst_mode='
  assert_file_contains "$MAIN_ACTIVITY" 'last_frame_ms='
  assert_file_contains "$MAIN_ACTIVITY" 'avg_frame_ms='
  assert_file_contains "$MAIN_ACTIVITY" 'max_frame_ms='
  assert_file_contains "$MAIN_ACTIVITY" 'slow_frames_16ms='
  assert_file_contains "$MAIN_ACTIVITY" 'slow_frames_32ms='
  assert_file_contains "$MAIN_ACTIVITY" 'recent_render_requests='
  assert_file_contains "$MAIN_ACTIVITY" 'bridge_mode='
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'if (browserSnapshotState.value != value)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'if (snapshot == latestSnapshot) return'
}

test_image_preview_bridge_asset() {
  assert_file_contains "$MKSESSION" '"codex-preview" to "codex-preview"'
  assert_file_contains "$MKSESSION" '"codex-push-image" to "codex-push-image"'
  assert_file_contains "$MKSESSION" '"codex-push-media" to "codex-push-media"'
  assert_file_contains "$MKSESSION" '"codex-browser" to "codex-browser"'
  assert_file_contains "$MKSESSION" '"codex-panel" to "codex-panel"'
  assert_file_contains "$MKSESSION" '"codex-session" to "codex-session"'
  assert_file_contains "$MKSESSION" '"codex-rtk" to "codex-rtk"'
  assert_file_contains "$MKSESSION" '"codex-context" to "codex-context"'
  assert_file_contains "$MKSESSION" '"rtk" to "rtk"'
  assert_file_contains "$MKSESSION" 'input.copyTo(output)'
  assert_file_contains "$INIT_ASSET" 'ensure_codex_preview'
  assert_file_contains "$INIT_ASSET" '[ ! -r /etc/profile ] || . /etc/profile'
  assert_file_contains "$INIT_ASSET" 'export PATH="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin:$PATH"'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'EmptyPreviewTray'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'GridCells.Adaptive'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'TextComposerTile'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'onSendText'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'text = if (previewCount <= 0) "文件"'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'Text("发送")'
  # 2.4.7: multi-select tray with top Send + batch note dialog
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'SendSelectedPreviewsDialog'
  assert_file_contains "$MEDIA_PREVIEW_PANE" '附加说明（可选）'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'onSendManyToAi'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'shortPreviewDisplayName'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'Checkbox'
  assert_file_not_contains "$MEDIA_PREVIEW_PANE" 'sendTarget = preview'
  assert_file_not_contains "$MEDIA_PREVIEW_PANE" 'onSendToAi(preview, "")'
  assert_file_contains "$MAIN_ACTIVITY" 'fun sendPreviewsToAi'
  assert_file_contains "$MAIN_ACTIVITY" '"$stamp-$kindToken.$ext"'
  assert_file_contains "$MEDIA_PREVIEW_PANE" '.height(28.dp)'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'color = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f)'
  assert_file_contains "$BROWSER_PANEL_PANE" '.height(28.dp)'
  assert_file_contains "$BROWSER_PANEL_PANE" 'BrowserTabChip'
  assert_file_not_contains "$BROWSER_PANEL_PANE" 'browserSessionManager::selectTabFromUi'
  assert_file_not_contains "$BROWSER_PANEL_PANE" 'browserSessionManager::closeTabFromUi'
  assert_file_contains "$TERMINAL_SCREEN" 'onSelectTab = mainActivity::selectBrowserTabFromUi'
  assert_file_contains "$TERMINAL_SCREEN" 'onCloseTab = mainActivity::closeBrowserTabFromUi'
  assert_file_contains "$BROWSER_PANEL_PANE" 'color = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'fun selectTabFromUi'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'fun closeTabFromUi'
  assert_file_contains "$MAIN_ACTIVITY" 'codex-preview path'
  assert_file_contains "$MAIN_ACTIVITY" 'writePreviewReference'
  assert_file_contains "$MAIN_ACTIVITY" 'submitPromptToSession'
  assert_file_contains "$MAIN_ACTIVITY" 'TRAY_SEND_ENTER_DELAY_MS'
  assert_file_contains "$MAIN_ACTIVITY" 'terminalView.postDelayed'
  assert_file_contains "$MAIN_ACTIVITY" 'terminalView.requestFocus()'
  assert_file_contains "$MAIN_ACTIVITY" 'terminalView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))'
  assert_file_contains "$MAIN_ACTIVITY" 'terminalView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))'
  assert_file_not_contains "$MAIN_ACTIVITY" 'session.write(prompt.trimEnd'
  assert_file_contains "$MAIN_ACTIVITY" 'sendComposerTextToAi'
  assert_file_contains "$MAIN_ACTIVITY" 'writeAgentPanelEvent'
  assert_file_contains "$MAIN_ACTIVITY" 'selectBrowserTabFromUi'
  assert_file_contains "$MAIN_ACTIVITY" 'closeBrowserTabFromUi'
  assert_file_contains "$MAIN_ACTIVITY" 'mediaPreviewOpened'
  assert_file_contains "$MAIN_ACTIVITY" 'mediaPreviewClosed'
  assert_file_contains "$MAIN_ACTIVITY" 'mediaPreviewShared'
  assert_file_contains "$MAIN_ACTIVITY" 'writeMediaPreviewResult'
  assert_file_contains "$MAIN_ACTIVITY" 'writeBrowserNeedsUserTransition'
  assert_file_contains "$MAIN_ACTIVITY" 'item_id='
  assert_file_contains "$MAIN_ACTIVITY" 'active_item='
  assert_file_contains "$MAIN_ACTIVITY" 'private fun syncMediaPreviewStatus'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "top_bar", state = "ready")'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "collapse", state = "done")'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "delete_item", state = "ready")'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "composer_sent", state = "done")'
  assert_file_contains "$MAIN_ACTIVITY" 'user_sent_text'
  assert_file_contains "$MAIN_ACTIVITY" 'restoreMediaPreviewCacheAfterColdStart'
  assert_file_contains "$MAIN_ACTIVITY" 'recoverMediaPreviewCache'
  assert_file_contains "$MAIN_ACTIVITY" 'clearAllMediaPreviewCache'
  assert_file_contains "$MAIN_ACTIVITY" 'deleteMediaPreviewCacheNow'
  assert_file_contains "$MAIN_ACTIVITY" 'MEDIA_PREVIEW_MAX_CACHE_BYTES'
  assert_file_contains "$MAIN_ACTIVITY" 'MEDIA_PREVIEW_MAX_CACHE_AGE_MS'
  assert_file_contains "$MAIN_ACTIVITY" 'localDir().child("browser").child("screenshots")'
  assert_file_contains "$MAIN_ACTIVITY" 'writePreviewReference(preview, previewReferenceId(preview))'
  assert_file_contains "$MAIN_ACTIVITY" 'visible='
  assert_file_contains "$MAIN_ACTIVITY" 'collapsed='
  assert_file_not_contains "$MAIN_ACTIVITY" '不要让我粘贴全文'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview path FILE_ID'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview [--present|--background] text --stdin'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview present|collapse|toggle|done|cancel|clear|close [REASON]'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview status|events|wait|result'
  assert_file_contains "$PREVIEW_ASSET" 'print_events_for_target files'
  assert_file_contains "$PREVIEW_ASSET" 'present=%s'
  assert_file_contains "$INIT_ASSET" 'codex-preview path FILE_ID'
  assert_file_contains "$INIT_ASSET" '[ -x "$bin_dir/codex-preview" ]'
  assert_file_contains "$INIT_ASSET" 'codex-preview [--present|--background] text --stdin'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'fun addMediaPreview(preview: TerminalMediaPreview): List<TerminalMediaPreview>'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'evicted.add(mediaPreviews.removeAt(0))'
  assert_file_not_contains "$TERMINAL_VIEW_MODEL" 'mediaPreviewExpanded = true'
  assert_file_not_contains "$TERMINAL_VIEW_MODEL" 'browserPanelExpanded = true'
  assert_file_not_contains "$TERMINAL_TOP_BAR" 'onPickFileClick'
  assert_file_not_contains "$MEDIA_PREVIEW_PANE" '预览托盘'
  assert_file_not_contains "$MEDIA_PREVIEW_PANE" 'Text("AI")'
  assert_file_not_contains "$MEDIA_PREVIEW_PANE" '发给 AI'
  assert_file_not_contains "$MEDIA_PREVIEW_PANE" '发送给 AI'
  assert_file_not_contains "$MAIN_ACTIVITY" '请查看我放入预览托盘'
  sh -n "$PREVIEW_ASSET" || fail "codex-preview shell syntax failed"
  sh -n "$PUSH_IMAGE_ASSET" || fail "codex-push-image shell syntax failed"
  sh -n "$PUSH_MEDIA_ASSET" || fail "codex-push-media shell syntax failed"
  sh -n "$BROWSER_ASSET" || fail "codex-browser shell syntax failed"
assert_file_contains "$BROWSER_ASSET" 'print_events_for_target browser'
  sh -n "$PANEL_ASSET" || fail "codex-panel shell syntax failed"
  sh -n "$SESSION_ASSET" || fail "codex-session shell syntax failed"
  sh -n "$RTK_ASSET" || fail "codex-rtk shell syntax failed"
  sh -n "$BROWSER_SMOKE" || fail "browser smoke shell syntax failed"
  sh -n "$DEVICE_SMOKE" || fail "device smoke shell syntax failed"
  sh -n "$INSTALLED_DEVICE_SMOKE" || fail "installed device smoke shell syntax failed"
  sh -n "$INIT_ASSET" || fail "init.sh shell syntax failed"
  assert_file_contains "$PREVIEW_ASSET" 'queue_dir="$bridge_dir/queue"'
  assert_file_contains "$PREVIEW_ASSET" 'queue_tmp="$queue_dir/.$safe_request_id.req.tmp.$$"'
  assert_file_contains "$PREVIEW_ASSET" 'queue_tmp="$queue_dir/.$safe_stamp.req.tmp.$$"'
  assert_file_contains "$PREVIEW_ASSET" 'cp "$req_tmp" "$legacy_tmp"'
  assert_file_contains "$PANEL_ASSET" 'queue_dir="$bridge_dir/queue"'
  assert_file_contains "$PANEL_ASSET" 'queue_tmp="$queue_dir/.$safe_request_id.req.tmp.$$"'
  assert_file_contains "$PANEL_ASSET" 'cp "$req_tmp" "$legacy_tmp"'
  assert_file_contains "$PANEL_ASSET" 'mv "$queue_tmp" "$req_file"'
  assert_file_contains "$SESSION_ASSET" 'queue_dir="$bridge_dir/queue"'
  assert_file_contains "$SESSION_ASSET" 'queue_tmp="$queue_dir/.$safe_request_id.req.tmp.$$"'
  assert_file_contains "$SESSION_ASSET" 'cp "$req_tmp" "$legacy_tmp"'
  assert_file_contains "$SESSION_ASSET" 'mv "$queue_tmp" "$req_file"'
  assert_file_contains "$BROWSER_ASSET" 'queue_tmp="$queue_dir/.$safe_request_id.req.tmp.$$"'
  assert_file_contains "$BROWSER_ASSET" 'mv "$queue_tmp" "$req_file"'
  assert_file_not_contains "$PREVIEW_ASSET" 'req_tmp="$queue_dir/'
  assert_file_not_contains "$PANEL_ASSET" 'req_tmp="$queue_dir/'
  assert_file_not_contains "$SESSION_ASSET" 'req_tmp="$queue_dir/'
  assert_file_not_contains "$BROWSER_ASSET" 'req_tmp="$queue_dir/'
  assert_file_not_contains "$PREVIEW_ASSET" 'cp "$req_file" "$legacy_tmp"'
  assert_file_not_contains "$PANEL_ASSET" 'cp "$req_file" "$legacy_tmp"'
  assert_file_not_contains "$SESSION_ASSET" 'cp "$req_file" "$legacy_tmp"'

  tmp="${TMPDIR:-/tmp}/codex-tui-static-image-preview.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/prefix" "$tmp/source"
  printf 'fake-image\n' > "$tmp/source/pic.png"
  printf 'fake-video\n' > "$tmp/source/clip.mp4"
  i=0
  while [ "$i" -lt 200 ]; do
    printf 'long text line %s\n' "$i"
    i=$((i + 1))
  done > "$tmp/source/notes.md"

  PREFIX="$tmp/prefix" sh "$INIT_ASSET" true || fail "init.sh should create preview commands before exec"
  [ -x "$tmp/prefix/local/bin/codex-preview" ] || fail "init.sh did not create codex-preview fallback"
  [ -x "$tmp/prefix/local/bin/codex-push-image" ] || fail "init.sh did not create codex-push-image wrapper"
  [ -x "$tmp/prefix/local/bin/codex-push-media" ] || fail "init.sh did not create codex-push-media wrapper"

  if ! output="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" "$tmp/source/pic.png")"; then
    fail "codex-preview should copy an image into preview bridge"
  fi

  [ -s "$tmp/prefix/local/media-preview/request" ] || fail "preview request file missing"
  image_path="$(sed -n 's/^path=//p' "$tmp/prefix/local/media-preview/request")"
  [ -s "$image_path" ] || fail "preview image copy missing"
  case "$image_path" in
    "$tmp/prefix/local/media-preview/files/"*.png) ;;
    *) fail "preview image path should use a unique png file: $image_path" ;;
  esac
  image_stamp="$(sed -n 's/^stamp=//p' "$tmp/prefix/local/media-preview/request")"
  resolved_path="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" path "$image_stamp")" || fail "codex-preview path should resolve image ref"
  [ "$resolved_path" = "$image_path" ] || fail "codex-preview path resolved wrong image path: $resolved_path"
  fallback_resolved_path="$(PREFIX="$tmp/prefix" "$tmp/prefix/local/bin/codex-preview" path "$image_stamp")" || fail "fallback codex-preview path should resolve image ref"
  [ "$fallback_resolved_path" = "$image_path" ] || fail "fallback codex-preview path resolved wrong image path: $fallback_resolved_path"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=show"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "present=1"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "queued=1"
  ls "$tmp/prefix/local/media-preview/queue/"*.req >/dev/null 2>&1 || fail "preview queue request file missing"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "kind=image"
  printf '%s\n' "$output" | grep -F '已发送到 Codex for TUI 文件面板' >/dev/null 2>&1 || fail "preview command did not report success"

  if ! output="$(PREFIX="$tmp/prefix" "$tmp/prefix/local/bin/codex-push-media" --background "$tmp/source/clip.mp4")"; then
    fail "codex-push-media should copy a video into preview bridge"
  fi

  video_path="$(sed -n 's/^path=//p' "$tmp/prefix/local/media-preview/request")"
  [ -s "$video_path" ] || fail "preview video copy missing"
  case "$video_path" in
    "$tmp/prefix/local/media-preview/files/"*.mp4) ;;
    *) fail "preview video path should use a unique mp4 file: $video_path" ;;
  esac
  assert_file_contains "$tmp/prefix/local/media-preview/request" "kind=video"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "present=0"

  if ! output="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" "$tmp/source/notes.md")"; then
    fail "codex-preview should copy a text file into preview bridge"
  fi

  text_path="$(sed -n 's/^path=//p' "$tmp/prefix/local/media-preview/request")"
  [ -s "$text_path" ] || fail "preview text copy missing"
  case "$text_path" in
    "$tmp/prefix/local/media-preview/files/"*.md) ;;
    *) fail "preview text path should use a unique md file: $text_path" ;;
  esac
  assert_file_contains "$tmp/prefix/local/media-preview/request" "kind=text"
  printf '%s\n' "$output" | grep -F 'long text line' >/dev/null 2>&1 && fail "codex-preview dumped text file content"

  if ! output="$(printf 'stdin long text line\nsecond line\n' | PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" --background text --stdin --name user-note.txt)"; then
    fail "codex-preview should accept stdin text into preview bridge"
  fi
  stdin_text_path="$(sed -n 's/^path=//p' "$tmp/prefix/local/media-preview/request")"
  [ -s "$stdin_text_path" ] || fail "stdin text copy missing"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "kind=text"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "present=0"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "name=user-note.txt"
  stdin_text_stamp="$(sed -n 's/^stamp=//p' "$tmp/prefix/local/media-preview/request")"
  stdin_resolved_path="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" path "$stdin_text_stamp")" || fail "codex-preview path should resolve stdin text ref"
  [ "$stdin_resolved_path" = "$stdin_text_path" ] || fail "stdin text ref resolved wrong path: $stdin_resolved_path"
  printf '%s\n' "$output" | grep -F 'stdin long text line' >/dev/null 2>&1 && fail "codex-preview stdin dumped text content"

  mkdir -p "$tmp/prefix/local/agent-panel"
  cat > "$tmp/prefix/local/agent-panel/events" <<'EOF'
source=files
mode=files
reason=file_event
---
source=browser
mode=browser
reason=browser_event
---
EOF
  preview_events="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" events)" || fail "codex-preview events failed"
  assert_contains "$preview_events" "file_event" "codex-preview events"
  assert_not_contains "$preview_events" "browser_event" "codex-preview events"

  if ! output="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" close)"; then
    fail "codex-preview close should write a clear request"
  fi
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=clear"
  printf '%s\n' "$output" | grep -F '已发送到 Codex for TUI 文件面板' >/dev/null 2>&1 || fail "preview close did not report success"

  if ! PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" collapse agent_test >/dev/null; then
    fail "codex-preview collapse should write a collapse request"
  fi
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=collapse"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "reason=agent_test"

  if ! PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" result >/dev/null; then
    fail "codex-preview result should be safe without result file"
  fi
  rm -rf "$tmp"
}

test_codex_ops_tool_assets() {
  for tool in "$DOCTOR_ASSET" "$CLEAN_ASSET" "$OPS_ASSET" "$OPS_LIB_ASSET"; do
    assert_nonempty_file "$tool"
    sh -n "$tool" || fail "$(basename "$tool") shell syntax failed"
  done
  sh -n "$OPS_SMOKE" || fail "ops smoke shell syntax failed"

  assert_file_contains "$MKSESSION" '"codex-doctor" to "codex-doctor"'
  assert_file_contains "$MKSESSION" '"codex-clean" to "codex-clean"'
  assert_file_contains "$MKSESSION" '"codex-ops" to "codex-ops"'
  assert_file_contains "$MKSESSION" '"codex-ops-lib" to "codex-ops-lib"'
  assert_file_contains "$MKSESSION" '"codex-dev-transfer" to "codex-dev-transfer"'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-common.sh" 'codex-doctor'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-common.sh" 'codex-clean'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-common.sh" 'codex-ops'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-common.sh" 'codex-dev-transfer'

  assert_file_contains "$CLEAN_ASSET" 'scan'
  assert_file_contains "$CLEAN_ASSET" 'apply'
  assert_file_contains "$CLEAN_ASSET" 'restore'
  assert_file_contains "$CLEAN_ASSET" 'trash'
  assert_file_contains "$CLEAN_ASSET" 'local/media-preview/files'
  assert_file_contains "$CLEAN_ASSET" 'local/media-preview/refs'
  assert_file_contains "$CLEAN_ASSET" 'local/browser/screenshots'
  assert_file_contains "$OPS_ASSET" 'status'
  assert_file_contains "$OPS_ASSET" 'events'
  assert_file_contains "$OPS_ASSET" 'resume_hint'
  assert_nonempty_file "$DEV_TRANSFER_ASSET"
  sh -n "$DEV_TRANSFER_ASSET" || fail "codex-dev-transfer shell syntax failed"
  sh -n "$DEV_TRANSFER_SMOKE" || fail "dev transfer smoke shell syntax failed"
  sh -n "$DEV_TRANSFER_SECURITY_SMOKE" || fail "dev transfer security smoke shell syntax failed"
  sh -n "$CONFIG_SMOKE" || fail "config smoke shell syntax failed"
  assert_file_contains "$DEV_TRANSFER_ASSET" 'codex-dev-transfer export [LABEL]'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'codex-dev-transfer export --include-secrets [--yes] [LABEL]'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'codex-dev-transfer import [--yes] [--no-backup] FILE|latest'
  assert_file_contains "$DEV_TRANSFER_ASSET" '/storage/emulated/0/Download/Codex/dev-transfer'
  assert_file_contains "$DEV_TRANSFER_ASSET" '默认导出会排除 auth.json'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'validate_archive'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'member_is_whitelisted'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'member_has_dotdot'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'symlink/hardlink'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'prune_default_secrets'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'copy_codex_home_safe'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'copy_codex_home_full'
  assert_file_contains "$DEV_TRANSFER_ASSET" '"$root/root/.codex/.tmp"'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'include_secrets=0'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'rewrite_payload_paths'
  assert_file_contains "$DEV_TRANSFER_ASSET" 'rollback'
  assert_file_contains "$DEV_TRANSFER_SMOKE" 'evil-unknown.tar.gz'
  assert_file_contains "$DEV_TRANSFER_SMOKE" 'evil-link.tar.gz'
  assert_file_contains "$DEV_TRANSFER_SMOKE" 'default import should not restore auth.json'
  assert_file_contains "$DEV_TRANSFER_SMOKE" 'payload/root/.codex/.tmp/'
  assert_file_contains "$DEV_TRANSFER_SMOKE" 'include-secrets import should restore auth.json'
  assert_file_contains "$DEV_TRANSFER_SECURITY_SMOKE" 'verify should reject'
  assert_file_contains "$DEV_TRANSFER_SECURITY_SMOKE" 'target parent is a file'
  assert_file_contains "$CONFIG_SMOKE" 'test_hook_quick_auth_writes_only_after_explicit_choice_and_backs_up'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-common.sh" 'CODEX_ZH_PROVIDER_NAME:=OpenAI'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_normalize_third_party_provider_name'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" '${CODEX_ZH_PROVIDER_NAME:-OpenAI}'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'name = "$CODEX_ZH_PROVIDER_ID"'
  assert_file_contains "$ROOT_DIR/tests/codex-for-tui-installer-smoke.sh" 'test_provider_name_normalization_keeps_custom_id_and_user_name'
  assert_file_contains "$INSTALLED_DEVICE_SMOKE" 'codex-doctor'
  assert_file_contains "$INSTALLED_DEVICE_SMOKE" 'codex-clean'
  assert_file_contains "$INSTALLED_DEVICE_SMOKE" 'codex-ops'
  assert_file_contains "$INSTALLED_DEVICE_SMOKE" 'codex-dev-transfer'
  assert_file_contains "$DEVICE_SMOKE" 'PACKAGE="${CODEX_TUI_PACKAGE:-com.gzy3894.codexfortui.test}"'
  assert_file_not_contains "$DEVICE_SMOKE" 'com.gzy3894.codexfortui.debug'
}

test_browser_bridge_asset() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-browser.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/prefix"

  if ! output="$(PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait open https://example.test)"; then
    fail "codex-browser should write an open request"
  fi
  [ -s "$tmp/prefix/local/browser/request" ] || fail "browser request file missing"
  ls "$tmp/prefix/local/browser/queue/"*.req >/dev/null 2>&1 || fail "browser queue request file missing"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=navigate"
  assert_file_contains "$tmp/prefix/local/browser/request" "queued=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=0"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://example.test"
  printf '%s\n' "$output" | grep -F '已发送到 Codex for TUI 浏览器' >/dev/null 2>&1 || fail "browser command did not report success"

  if ! output="$(PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait open https://baidu.example.test codex-browser status)"; then
    fail "codex-browser should tolerate accidental chained status after open"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=navigate"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=0"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://baidu.example.test"
  printf '%s\n' "$output" | grep -F 'status 要另起一行执行' >/dev/null 2>&1 || fail "browser command did not print chained status hint"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait open --present https://visible.example.test >/dev/null; then
    fail "codex-browser open --present should write a visible open request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=navigate"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://visible.example.test"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait present user_review >/dev/null; then
    fail "codex-browser present should write a present request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=present"
  assert_file_contains "$tmp/prefix/local/browser/request" "reason=user_review"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait collapse agent_review >/dev/null; then
    fail "codex-browser collapse should write a collapse request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=collapse"
  assert_file_contains "$tmp/prefix/local/browser/request" "reason=agent_review"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait toggle agent_toggle >/dev/null; then
    fail "codex-browser toggle should write a toggle request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=toggle"
  assert_file_contains "$tmp/prefix/local/browser/request" "reason=agent_toggle"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth https://login.example.test >/dev/null; then
    fail "codex-browser should write an auth request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://login.example.test"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth-open --reason "Codex 官方登录" --code "ABCD-EFGH" https://device.example.test >/dev/null; then
    fail "codex-browser should write an auth-open request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth_open"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "open_now=0"
  assert_file_contains "$tmp/prefix/local/browser/request" "reason=Codex 官方登录"
  assert_file_contains "$tmp/prefix/local/browser/request" "code=ABCD-EFGH"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://device.example.test"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth-open --open-now --reason "Codex 官方登录" --code "ABCD-EFGH" https://device.example.test >/dev/null; then
    fail "codex-browser should write an auth-open --open-now request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth_open"
  assert_file_contains "$tmp/prefix/local/browser/request" "open_now=1"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth-done test-auth-request >/dev/null; then
    fail "codex-browser should write an auth-done request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth_done"
  assert_file_contains "$tmp/prefix/local/browser/request" "auth_request_id=test-auth-request"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth-reopen test-auth-request >/dev/null; then
    fail "codex-browser should write an auth-reopen request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth_reopen"
  assert_file_contains "$tmp/prefix/local/browser/request" "auth_request_id=test-auth-request"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth-cancel test-auth-request >/dev/null; then
    fail "codex-browser should write an auth-cancel request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth_cancel"
  assert_file_contains "$tmp/prefix/local/browser/request" "auth_request_id=test-auth-request"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" auth-status missing-auth-request >/dev/null; then
    fail "codex-browser auth-status should be safe without status file"
  fi

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait external https://external.example.test >/dev/null; then
    fail "codex-browser should write an external request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=external"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://external.example.test"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait external-confirm external-test-request >/dev/null; then
    fail "codex-browser should write an external-confirm request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=external_confirm"
  assert_file_contains "$tmp/prefix/local/browser/request" "external_request_id=external-test-request"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait external-cancel external-test-request >/dev/null; then
    fail "codex-browser should write an external-cancel request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=external_cancel"
  assert_file_contains "$tmp/prefix/local/browser/request" "external_request_id=external-test-request"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait type '#q' 'hello world' >/dev/null; then
    fail "codex-browser should write a type request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=type"
  assert_file_contains "$tmp/prefix/local/browser/request" "selector=#q"
  assert_file_contains "$tmp/prefix/local/browser/request" "text=hello world"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait list-tabs >/dev/null; then
    fail "codex-browser should write a list-tabs request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=list_tabs"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait screenshot --push --background >/dev/null; then
    fail "codex-browser should write a screenshot push request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=screenshot"
  assert_file_contains "$tmp/prefix/local/browser/request" "push=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "present_files=0"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait cookies verify https://cookie.example.test >/dev/null; then
    fail "codex-browser should write a cookie verify request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=cookies_verify"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://cookie.example.test"

  printf 'document.body.dataset.codexUserscript="ok";\n' > "$tmp/userscript.js"
  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait userscript add test-script example.test "$tmp/userscript.js" >/dev/null; then
    fail "codex-browser should write a userscript add request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=userscript_add"
  assert_file_contains "$tmp/prefix/local/browser/request" "name=test-script"
  assert_file_contains "$tmp/prefix/local/browser/request" "match=example.test"
  assert_file_contains "$tmp/prefix/local/browser/request" "path=$tmp/prefix/local/browser/userscripts/incoming/"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait user-wait '请完成验证' >/dev/null; then
    fail "codex-browser should write a user wait request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=user_wait"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "message=请完成验证"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait wait-user '请完成验证' >/dev/null; then
    fail "codex-browser should accept wait-user alias"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=user_wait"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "message=请完成验证"

  PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" status >/dev/null || fail "codex-browser status should be safe without status file"
  PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" events >/dev/null || fail "codex-browser events should be safe without events file"
  mkdir -p "$tmp/prefix/local/agent-panel"
  cat > "$tmp/prefix/local/agent-panel/events" <<'EOF'
source=files
mode=files
reason=file_event
---
source=browser
mode=browser
reason=browser_event
---
EOF
  browser_events="$(PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" events)" || fail "codex-browser events failed"
  assert_contains "$browser_events" "browser_event" "codex-browser events"
  assert_not_contains "$browser_events" "file_event" "codex-browser events"
  PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" result >/dev/null || fail "codex-browser result should be safe without result file"
  PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" result missing-id >/dev/null || fail "codex-browser result REQUEST_ID should be safe without result file"
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'CustomTabsIntent.Builder'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'request["open_now"] == "1"'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '.put("openNow", openNow)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'shouldHandleOutsideWebView'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'onShowFileChooser'
  assert_file_contains "$BROWSER_SMOKE" 'persist.html'
  assert_file_contains "$BROWSER_SMOKE" 'wait_browser_result_contains'
  assert_file_contains "$BROWSER_SMOKE" 'browser_event_count'
  assert_file_contains "$BROWSER_SMOKE" 'wait_browser_event_after'
  assert_file_contains "$BROWSER_SMOKE" 'first_tab_id'
  assert_file_contains "$BROWSER_SMOKE" 'select-tab "$first_tab_id"'
  assert_file_contains "$BROWSER_SMOKE" 'type=agent_presented'
  assert_file_contains "$BROWSER_SMOKE" 'type=agent_collapsed'
  assert_file_contains "$BROWSER_SMOKE" 'type=agent_user_wait'
  assert_file_contains "$BROWSER_SMOKE" 'type=agent_done'
  assert_file_contains "$BROWSER_SMOKE" 'run_browser close'
  assert_file_contains "$BROWSER_SMOKE" 'cookie was not reused after browser restart'
  assert_file_contains "$BROWSER_SMOKE" 'localStorage.getItem'
  assert_file_contains "$BROWSER_SMOKE" 'queue_ids'
  assert_file_not_contains "$BROWSER_SMOKE" 'select-tab 1'
  assert_file_not_contains "$TERMINAL_BROWSER_SESSION" 'MAX_BROWSER_TABS'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'CookieManager.getInstance().flush()'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '"cookies_verify" -> cookieVerify'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '"userscript_add" -> userScriptAdd'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'appendHistory(tab)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'applyUserScripts(tab) {'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'completeLoadWaiterIfCurrent(tab, finishedToken)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'tab.lastError?.takeIf { !it.startsWith("userscript", ignoreCase = true) }'
  assert_file_not_contains "$TERMINAL_BROWSER_SESSION" 'Page load timed out before userscript completion'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'function codexRunUserScript()'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'DOMContentLoaded'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'buildUserScriptJavascript'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'new Function(codexSource'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'decodeJsString(raw)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'recordUserScriptResult'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'finishOnce(false, "callback timeout", null)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'val deadline = System.currentTimeMillis() + 2500'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'pushToFiles'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '"present" -> present'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '"collapse" -> JSONObject().put("collapsed", true)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '"user_collapse"'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'status == "collapsed" -> "collapsed"'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'activeUserRequestId'
  assert_file_not_contains "$BROWSER_ASSET" 'cp "$req_file" "$legacy_tmp"'
  assert_file_contains "$BROWSER_ASSET" 'cp "$req_tmp" "$legacy_tmp"'
  assert_file_contains "$MAIN_ACTIVITY" 'queueDir.listFiles()'
  assert_file_contains "$MAIN_ACTIVITY" 'mediaPreviewQueueObserver'
  assert_file_contains "$MAIN_ACTIVITY" 'sessionFoldQueueObserver'
  assert_file_contains "$MAIN_ACTIVITY" 'mediaPreviewProcessedRequestIds'
  assert_file_contains "$MAIN_ACTIVITY" 'sessionFoldProcessedRequestIds'
  assert_file_contains "$MAIN_ACTIVITY" 'persistBrowserSnapshot(snapshot)'
  assert_file_contains "$MAIN_ACTIVITY" 'shouldSkipTerminalBrowserSnapshotPersist(browserDir, snapshot, requestId)'
  assert_file_contains "$MAIN_ACTIVITY" 'browserResultHasExplicitAction(browserDir, requestId)'
  assert_file_contains "$MAIN_ACTIVITY" '.replace("\n", "\\n")'
  assert_file_contains "$MAIN_ACTIVITY" 'runCatching {'
  assert_file_contains "$MAIN_ACTIVITY" 'writeBrowserBridgeError'
  assert_file_contains "$MAIN_ACTIVITY" 'file.name.removeSuffix(".req")'
  assert_file_contains "$MAIN_ACTIVITY" 'isBrowserRequestProcessed'
  assert_file_contains "$MAIN_ACTIVITY" 'maybePushBrowserScreenshotToFiles'
  assert_file_contains "$MAIN_ACTIVITY" 'browserDir.child("results")'
  assert_file_contains "$MAIN_ACTIVITY" 'action == "present"'
  assert_file_contains "$MAIN_ACTIVITY" 'action == "collapse"'
  assert_file_contains "$MAIN_ACTIVITY" 'requestedAction) {'
  assert_file_contains "$MAIN_ACTIVITY" '"auth_open", "auth_reopen"'
  assert_file_contains "$MAIN_ACTIVITY" 'val suppressPresent = action in setOf("collapse", "user_done", "user_cancelled", "auth_collapse", "auth_done", "auth_cancel", "auth_cancelled", "external_cancel", "close")'
  assert_file_contains "$MAIN_ACTIVITY" 'effectiveAction in setOf("present", "user_wait", "auth_open", "auth_reopen")'
  assert_file_contains "$MAIN_ACTIVITY" 'snapshot?.optBoolean("needsUser") == true'
  assert_file_contains "$MAIN_ACTIVITY" 'val shouldCollapse = action in setOf("collapse", "user_done", "user_cancelled", "auth_collapse", "auth_done", "auth_cancel", "auth_cancelled", "external_cancel")'
  assert_file_contains "$MAIN_ACTIVITY" 'markBrowserAuthCollapsed'
  assert_file_contains "$MAIN_ACTIVITY" '.put("activeItem", activeItem)'
  assert_file_contains "$MAIN_ACTIVITY" 'append("active_item=").append(refValue(activeItem))'
  assert_file_contains "$MAIN_ACTIVITY" 'append("auth_state=").append(refValue'
  assert_file_contains "$MAIN_ACTIVITY" 'append("user_action=").append(refValue'
  assert_file_contains "$MAIN_ACTIVITY" 'append("tabs_count=").append(tabsCount)'
  assert_file_contains "$MAIN_ACTIVITY" 'append("item_id=").append(refId)'
  rm -rf "$tmp"
}

test_browser_background_asset() {
  [ -s "$ROOT_DIR/android-app/core/main/src/main/res/drawable-nodpi/codex_tui_tonal_background.png" ] || fail "default terminal background asset missing"
  assert_file_contains "$TERMINAL_SCREEN" 'R.drawable.codex_tui_tonal_background'
  assert_file_contains "$TERMINAL_SCREEN" 'customBackground.exists()'
  assert_file_contains "$ROOT_DIR/android-app/core/main/src/main/java/com/rk/settings/Settings.kt" 'Preference.getFloat(key = "wallTransparency", default = 1f)'
}

test_agent_panel_bridge_asset() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-agent-panel.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/prefix/local/media-preview" "$tmp/prefix/local/browser" "$tmp/prefix/local/agent-panel"

  assert_file_contains "$PANEL_ASSET" 'codex-panel present|collapse|toggle files|browser [REASON]'
  assert_file_contains "$PANEL_ASSET" 'codex-panel done|cancel files|browser [REASON]'
  assert_file_contains "$PANEL_ASSET" 'codex-panel clear files [REASON]'
  assert_file_contains "$PANEL_ASSET" 'codex-panel close browser [REASON]'
  assert_file_contains "$PANEL_ASSET" 'codex-panel select|remove files FILE_ID'
  assert_file_contains "$PANEL_ASSET" 'print_events_for_target'
  assert_file_contains "$PANEL_ASSET" 'source=files'
  assert_file_contains "$PANEL_ASSET" 'source=browser'

  if ! output="$(PREFIX="$tmp/prefix" sh "$PANEL_ASSET" present files agent_review)"; then
    fail "codex-panel should write files present request"
  fi
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=present"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "present=1"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "reason=agent_review"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "queued=1"
  ls "$tmp/prefix/local/media-preview/queue/"*.req >/dev/null 2>&1 || fail "codex-panel files queue request file missing"
  printf '%s\n' "$output" | grep -F '已发送到 Codex for TUI Agent 面板' >/dev/null 2>&1 || fail "codex-panel did not report success"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" collapse files agent_collapse >/dev/null || fail "codex-panel files collapse failed"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=collapse"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "present=0"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" select files abc.123 >/dev/null || fail "codex-panel files select failed"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=select"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "item_id=abc.123"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" remove files abc.123 >/dev/null || fail "codex-panel files remove failed"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=remove"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" clear files agent_clear >/dev/null || fail "codex-panel files clear failed"
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=clear"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" present browser agent_browser >/dev/null || fail "codex-panel browser present failed"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=present"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=1"
  assert_file_contains "$tmp/prefix/local/browser/request" "queued=1"
  ls "$tmp/prefix/local/browser/queue/"*.req >/dev/null 2>&1 || fail "codex-panel browser queue request file missing"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" collapse browser agent_browser >/dev/null || fail "codex-panel browser collapse failed"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=collapse"
  assert_file_contains "$tmp/prefix/local/browser/request" "present=0"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" done browser agent_done >/dev/null || fail "codex-panel browser done failed"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=user_done"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" cancel browser agent_cancel >/dev/null || fail "codex-panel browser cancel failed"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=user_cancelled"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" close browser agent_close >/dev/null || fail "codex-panel browser close failed"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=close"

  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" status >/dev/null || fail "codex-panel status should be safe without status file"
  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" events >/dev/null || fail "codex-panel events should be safe without events file"
  cat > "$tmp/prefix/local/agent-panel/events" <<'EOF'
source=files
mode=files
reason=file_event
---
source=browser
mode=browser
reason=browser_event
---
EOF
  panel_file_events="$(PREFIX="$tmp/prefix" sh "$PANEL_ASSET" events files)" || fail "codex-panel events files failed"
  assert_contains "$panel_file_events" "file_event" "codex-panel events files"
  assert_not_contains "$panel_file_events" "browser_event" "codex-panel events files"
  panel_browser_events="$(PREFIX="$tmp/prefix" sh "$PANEL_ASSET" events browser)" || fail "codex-panel events browser failed"
  assert_contains "$panel_browser_events" "browser_event" "codex-panel events browser"
  assert_not_contains "$panel_browser_events" "file_event" "codex-panel events browser"
  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" result files >/dev/null || fail "codex-panel files result should be safe without result file"
  PREFIX="$tmp/prefix" sh "$PANEL_ASSET" result browser >/dev/null || fail "codex-panel browser result should be safe without result file"

  rm -rf "$tmp"
}

test_session_fold_bridge_asset() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-session-fold.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/prefix/local/session-fold"

  assert_file_contains "$SESSION_ASSET" 'codex-session start [--run RUN_ID] [TITLE]'
  assert_file_contains "$SESSION_ASSET" 'codex-session add thinking|tool|text|file|browser|final --run RUN_ID'
  assert_file_contains "$SESSION_ASSET" 'codex-session timeline collapse|expand|toggle [REASON]'
  assert_file_contains "$SESSION_ASSET" 'codex-session status|events|wait|result'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'val sessionFoldRuns'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'sessionFoldTimelineCollapsed'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'data class TerminalSessionFoldRun'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'data class TerminalSessionFoldItem'
  assert_file_contains "$TERMINAL_SCREEN" 'SessionFoldTimeline'
  assert_file_contains "$TERMINAL_SCREEN" 'onTimelineToggle = mainActivity::toggleSessionFoldTimeline'
  assert_file_contains "$MAIN_ACTIVITY" 'private suspend fun pollSessionFoldRequest'
  assert_file_contains "$MAIN_ACTIVITY" 'writeSessionFoldEvent'
  assert_file_contains "$MAIN_ACTIVITY" 'toggleSessionFoldRun'
  assert_file_contains "$MAIN_ACTIVITY" 'toggleSessionFoldTimeline'
  assert_file_contains "$MAIN_ACTIVITY" 'timeline_collapsed='
  assert_file_contains "$MAIN_ACTIVITY" '"timeline_collapse", "timeline_expand", "timeline_toggle"'
  assert_file_contains "$MAIN_ACTIVITY" 'clearSessionFoldTimeline'

  if ! output="$(PREFIX="$tmp/prefix" sh "$SESSION_ASSET" start --run run-1 '测试会话')"; then
    fail "codex-session start should write request"
  fi
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=start"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "run_id=run-1"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "queued=1"
  ls "$tmp/prefix/local/session-fold/queue/"*.req >/dev/null 2>&1 || fail "codex-session queue request file missing"
  printf '%s\n' "$output" | grep -F 'run_id=run-1' >/dev/null 2>&1 || fail "codex-session start did not print run id"

  if ! PREFIX="$tmp/prefix" sh "$SESSION_ASSET" add tool --run run-1 --title '命令' --summary '成功' --status done >/dev/null; then
    fail "codex-session add tool should write request"
  fi
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=add"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "kind=tool"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "summary=成功"

  if ! output="$(printf 'very long private text\nsecond line\n' | PREFIX="$tmp/prefix" sh "$SESSION_ASSET" add text --run run-1 --stdin --title note)"; then
    fail "codex-session add text --stdin should write request"
  fi
  assert_file_contains "$tmp/prefix/local/session-fold/request" "kind=text"
  text_path="$(sed -n 's/^path=//p' "$tmp/prefix/local/session-fold/request")"
  [ -s "$text_path" ] || fail "codex-session stdin text file missing"
  printf '%s\n' "$output" | grep -F 'very long private text' >/dev/null 2>&1 && fail "codex-session dumped stdin text"

  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" done run-1 '完成' >/dev/null || fail "codex-session done failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=done"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" collapse run-1 >/dev/null || fail "codex-session collapse failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=collapse"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" timeline collapse agent_fold >/dev/null || fail "codex-session timeline collapse failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=timeline_collapse"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" timeline expand agent_expand >/dev/null || fail "codex-session timeline expand failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=timeline_expand"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" timeline toggle agent_toggle >/dev/null || fail "codex-session timeline toggle failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=timeline_toggle"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" remove run-1 >/dev/null || fail "codex-session remove failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=remove"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" clear test_clear >/dev/null || fail "codex-session clear failed"
  assert_file_contains "$tmp/prefix/local/session-fold/request" "action=clear"

  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" status >/dev/null || fail "codex-session status should be safe without status file"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" events >/dev/null || fail "codex-session events should be safe without events file"
  PREFIX="$tmp/prefix" sh "$SESSION_ASSET" result >/dev/null || fail "codex-session result should be safe without result file"
  rm -rf "$tmp"
}

test_codex_rtk_bridge_asset() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-rtk.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/bin" "$tmp/empty"

  assert_file_contains "$RTK_ASSET" 'codex-rtk status|enable|disable|verify|hook'
  assert_file_contains "$RTK_ASSET" 'permissionDecision":"allow"'
  assert_file_contains "$RTK_ASSET" 'updatedInput'
  assert_file_contains "$RTK_ASSET" 'RTK_DISABLED'
  assert_file_contains "$RTK_ASSET" 'codex-for-tui-rtk-hook begin'
  assert_file_contains "$RTK_ASSET" 'rtk_hook_source='

  sample='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'
  output="$(printf '%s' "$sample" | CODEX_RTK_NO_FALLBACK=1 RTK_DISABLED=0 PREFIX="$tmp/no-prefix" PATH="$tmp/empty:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" hook)"
  [ -z "$output" ] || fail "codex-rtk hook should fail open when rtk is missing"

  cat > "$tmp/bin/rtk" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  --version)
    printf '%s\n' 'rtk 0.43.0'
    ;;
  rewrite)
    if [ "${2:-}" = "git status" ]; then
      printf '%s\n' 'rtk git status'
      exit 3
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod 755 "$tmp/bin/rtk"

  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" status >"$tmp/status" || fail "codex-rtk status failed"
  assert_file_contains "$tmp/status" 'rtk_hook=disabled'
  assert_file_contains "$tmp/status" 'rtk_hook_source=disabled'

  output="$(printf '%s' "$sample" | RTK_DISABLED=0 PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" hook)"
  printf '%s\n' "$output" | grep -F "\"updatedInput\":{\"command\":\"$tmp/bin/rtk git status\"}" >/dev/null 2>&1 || fail "codex-rtk hook did not return absolute updatedInput"

  self_sample="{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$tmp/bin/rtk git status\"}}"
  output="$(printf '%s' "$self_sample" | RTK_DISABLED=0 PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" hook)"
  [ -z "$output" ] || fail "codex-rtk hook should not rewrite absolute rtk commands"

  find_sample='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"find /tmp -type f -exec ls -l {} \\;"}}'
  output="$(printf '%s' "$find_sample" | RTK_DISABLED=0 PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" hook)"
  [ -z "$output" ] || fail "codex-rtk hook should not rewrite unsafe find commands"

  PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" enable >/dev/null || fail "codex-rtk enable failed"
  assert_file_contains "$tmp/home/.codex/config.toml" 'hooks = true'
  assert_file_contains "$tmp/home/.codex/config.toml" 'codex-for-tui-rtk-hook begin'
  assert_file_contains "$tmp/home/.codex/config.toml" 'command = "codex-rtk hook"'
  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" status >"$tmp/status" || fail "codex-rtk config status failed"
  assert_file_contains "$tmp/status" 'rtk_hook=enabled'
  assert_file_contains "$tmp/status" 'rtk_hook_source=config'

  cat > "$tmp/requirements.toml" <<'EOF'
[features]
hooks = true

# codex-for-tui-managed-hooks begin
[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "codex-rtk hook"
timeout = 5
# codex-for-tui-managed-hooks end
EOF
  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" status >"$tmp/status" || fail "codex-rtk both status failed"
  assert_file_contains "$tmp/status" 'rtk_hook=enabled'
  assert_file_contains "$tmp/status" 'rtk_hook_source=both'

  PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" disable >/dev/null || fail "codex-rtk disable failed"
  assert_file_not_contains "$tmp/home/.codex/config.toml" 'codex-for-tui-rtk-hook begin'
  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" PREFIX="$tmp/no-prefix" PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$RTK_ASSET" status >"$tmp/status" || fail "codex-rtk requirements status failed"
  assert_file_contains "$tmp/status" 'rtk_hook=enabled'
  assert_file_contains "$tmp/status" 'rtk_hook_source=requirements'

  rm -rf "$tmp"
}

test_codex_context_bridge_asset() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-context.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/prefix/local"

  assert_file_contains "$CONTEXT_ASSET" 'codex-context status|report|events|hook|enable|disable|verify'
  assert_file_contains "$CONTEXT_ASSET" 'codex-for-tui-context-hook begin'
  assert_file_contains "$CONTEXT_ASSET" '[[hooks.PreCompact]]'
  assert_file_contains "$CONTEXT_ASSET" '[[hooks.PostCompact]]'
  assert_file_contains "$CONTEXT_ASSET" '[[hooks.SessionStart]]'
  assert_file_contains "$CONTEXT_ASSET" 'matcher = "manual|auto"'
  assert_file_contains "$CONTEXT_ASSET" 'matcher = "startup|resume|compact"'
  assert_file_contains "$CONTEXT_ASSET" 'context_hook_source='
  assert_file_contains "$CONTEXT_ASSET" 'context_auto_detection=enabled'
  assert_file_contains "$CONTEXT_ASSET" 'agent_prepare_required='
  assert_file_contains "$CONTEXT_ASSET" 'compact_remote_count='
  assert_file_contains "$CONTEXT_ASSET" 'session_compact_count='
  assert_file_contains "$CONTEXT_ASSET" 'pre_compact_unknown_trigger_count='
  assert_file_contains "$CONTEXT_ASSET" 'post_compact_manual_trigger_count='
  assert_file_contains "$CONTEXT_ASSET" 'model_effective_context_window='
  assert_file_contains "$CONTEXT_ASSET" 'model_auto_compact_source='
  assert_file_contains "$CONTEXT_ASSET" 'catalog inspect'
  assert_file_contains "$CONTEXT_ASSET" '/system/bin/date -d "@$epoch"'
  assert_file_not_contains "$CONTEXT_ASSET" '/sessions'
  assert_file_not_contains "$CONTEXT_ASSET" 'rollout-'

  HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" enable >/dev/null || fail "codex-context enable failed"
  assert_file_contains "$tmp/home/.codex/config.toml" 'hooks = true'
  assert_file_contains "$tmp/home/.codex/config.toml" 'codex-for-tui-context-hook begin'
  assert_file_contains "$tmp/home/.codex/config.toml" 'command = "codex-context hook"'
  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" status >"$tmp/status" || fail "codex-context config status failed"
  assert_file_contains "$tmp/status" 'context_hook=enabled'
  assert_file_contains "$tmp/status" 'context_hook_source=config'

  sample='{"hook_event_name":"PreCompact","trigger":"auto","compact_location":"remote","session_id":"alpha"}'
  printf '%s' "$sample" | PREFIX="$tmp/prefix" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" hook
  assert_file_contains "$tmp/home/.codex/context-state/events" 'phase=pre_compact'
  assert_file_contains "$tmp/home/.codex/context-state/events" 'compact_location=remote'
  assert_file_contains "$tmp/prefix/local/session-fold/events" 'source=context'
  assert_file_contains "$tmp/prefix/local/session-fold/events" 'type=context_pre_compact'
  assert_file_contains "$tmp/prefix/local/session-fold/events" 'compact_location=remote'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'context_auto_detection=enabled'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'agent_prepare_required=true'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'agent_prepare_reason=auto_compact_about_to_run'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'pre_compact_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'pre_compact_auto_trigger_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'compact_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'compact_remote_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_compact_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_compact_remote_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'last_compact_phase=pre_compact'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'last_compact_trigger=auto'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'last_compact_location=remote'
  HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" report >"$tmp/report" || fail "codex-context report failed"
  assert_file_contains "$tmp/report" '触发了一次远程压缩，当前会话已压缩1次。'

  sample='{"hook_event_name":"PostCompact","trigger":"manual","compact_location":"remote","session_id":"alpha"}'
  printf '%s' "$sample" | PREFIX="$tmp/prefix" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" hook
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'post_compact_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'post_compact_manual_trigger_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'compact_completed_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'agent_prepare_required=false'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'last_compact_phase=pre_compact'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'last_compact_trigger=auto'

  sample='{"hook_event_name":"PreCompact","trigger":"unexpected","compact_location":"local","session_id":"alpha"}'
  printf '%s' "$sample" | PREFIX="$tmp/prefix" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" hook
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'pre_compact_unknown_trigger_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'compact_local_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_compact_count=2'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_compact_local_count=1'
  HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" report >"$tmp/report" || fail "codex-context second report failed"
  assert_file_contains "$tmp/report" '触发了一次本地压缩，当前会话已压缩2次。'

  sample='{"hook_event_name":"PreCompact","trigger":"auto","session_id":"alpha"}'
  printf '%s' "$sample" | PREFIX="$tmp/prefix" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" hook
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'compact_unknown_location_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_compact_unknown_location_count=1'
  HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" report >"$tmp/report" || fail "codex-context unknown-location report failed"
  assert_file_contains "$tmp/report" '触发了一次未知来源压缩，当前会话已压缩3次。'

  sample='{"hook_event_name":"PostCompact","trigger":"unknown","compact_location":"local","session_id":"alpha"}'
  printf '%s' "$sample" | PREFIX="$tmp/prefix" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" hook
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'post_compact_unknown_trigger_count=1'

  sample='{"hook_event_name":"SessionStart","trigger":"compact","session_id":"alpha"}'
  printf '%s' "$sample" | PREFIX="$tmp/prefix" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" hook
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_start_count=1'
  assert_file_contains "$tmp/home/.codex/context-state/metrics" 'session_start_compact_count=1'

  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" status >"$tmp/status" || fail "codex-context status failed"
  assert_file_contains "$tmp/status" 'context_hook=enabled'
  assert_file_contains "$tmp/status" 'context_hook_source=config'
  assert_file_contains "$tmp/status" 'compact_count=3'
  assert_file_contains "$tmp/status" 'compact_remote_count=1'
  assert_file_contains "$tmp/status" 'compact_local_count=1'
  assert_file_contains "$tmp/status" 'compact_unknown_location_count=1'
  assert_file_contains "$tmp/status" 'session_compact_count=3'
  assert_file_contains "$tmp/status" 'compact_completed_count=2'
  assert_file_contains "$tmp/status" 'post_compact_manual_trigger_count=1'
  assert_file_contains "$tmp/status" 'session_start_compact_count=1'
  cat > "$tmp/requirements.toml" <<'EOF'
[features]
hooks = true

# codex-for-tui-managed-hooks begin
[[hooks.PreCompact]]
matcher = "manual|auto"

[[hooks.PreCompact.hooks]]
type = "command"
command = "codex-context hook"
timeout = 5
# codex-for-tui-managed-hooks end
EOF
  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" status >"$tmp/status" || fail "codex-context both status failed"
  assert_file_contains "$tmp/status" 'context_hook=enabled'
  assert_file_contains "$tmp/status" 'context_hook_source=both'
  HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" disable >/dev/null || fail "codex-context disable failed"
  assert_file_not_contains "$tmp/home/.codex/config.toml" 'codex-for-tui-context-hook begin'
  CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" sh "$CONTEXT_ASSET" status >"$tmp/status" || fail "codex-context requirements status failed"
  assert_file_contains "$tmp/status" 'context_hook=enabled'
  assert_file_contains "$tmp/status" 'context_hook_source=requirements'

  mkdir -p "$tmp/cap-home/.codex"
  printf '%s\n' \
    'model = "gpt-5.6-sol"' \
    'model_reasoning_effort = "ultra"' > "$tmp/cap-home/.codex/config.toml"
  CODEX_CONFIG_ENGINE_ROOT="$SCRIPT_DIR" \
    HOME="$tmp/cap-home" \
    CODEX_HOME="$tmp/cap-home/.codex" \
    sh "$CONTEXT_ASSET" status > "$tmp/cap-status" ||
    fail "codex-context model capability status failed"
  assert_file_contains "$tmp/cap-status" 'model=gpt-5.6-sol'
  assert_file_contains "$tmp/cap-status" 'model_capability_mode=exact'
  assert_file_contains "$tmp/cap-status" 'model_catalog_source=bundled-official'
  assert_file_contains "$tmp/cap-status" 'model_context_window=372000'
  assert_file_contains "$tmp/cap-status" 'model_effective_context_window=353400'
  assert_file_contains "$tmp/cap-status" 'model_effective_context_window_percent=95'
  assert_file_contains "$tmp/cap-status" 'model_auto_compact_token_limit=334800'
  assert_file_contains "$tmp/cap-status" 'model_auto_compact_source=derived-90-percent'
  assert_file_contains "$tmp/cap-status" 'model_reasoning_levels=low,medium,high,xhigh,max,ultra'

  printf '%s\n' 'model_auto_compact_token_limit = 220000' >> "$tmp/cap-home/.codex/config.toml"
  CODEX_CONFIG_ENGINE_ROOT="$SCRIPT_DIR" \
    HOME="$tmp/cap-home" \
    CODEX_HOME="$tmp/cap-home/.codex" \
    sh "$CONTEXT_ASSET" status > "$tmp/cap-fixed-status" ||
    fail "codex-context fixed compact status failed"
  assert_file_contains "$tmp/cap-fixed-status" 'model_auto_compact_token_limit=220000'
  assert_file_contains "$tmp/cap-fixed-status" 'model_auto_compact_source=config-fixed'

  sh "$CONTEXT_ASSET" verify >/dev/null || fail "codex-context verify failed"
  rm -rf "$tmp"
}

test_codex_config_default_hooks_survive_profile_use() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-config-hooks.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/bin"
  cat > "$tmp/bin/codex-rtk" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  cat > "$tmp/bin/codex-context" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod 755 "$tmp/bin/codex-rtk" "$tmp/bin/codex-context"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-download.sh"
    . "$SCRIPT_DIR/lib/codex-zh-config.sh"
    export PATH="$tmp/bin:$PATH"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_ACTIVE_SCRIPT_DIR="$SCRIPT_DIR"
    export CODEX_ZH_SCRIPT_INSTALL_ROOT="$tmp/scripts"
    export CODEX_FOR_TUI_REQUIREMENTS_FILE="$tmp/requirements.toml"
    codex_config_v2_prepare
    work="$(codex_config_v2_work_root)"
    codex_config_v2_run "$work/create-first.json" \
      profile create \
      --name keep-hooks \
      --mode official \
      --model gpt-5.4 \
      --reasoning-effort high \
      --activate
    codex_config_v2_post_materialize
    codex_config_v2_run "$work/create-second.json" \
      profile create \
      --name second \
      --mode official \
      --model gpt-5.5 \
      --reasoning-effort xhigh
    codex_config_v2_run "$work/activate-second.json" profile activate second
    codex_config_v2_post_materialize
    codex_config_engine profile show second > "$tmp/second.json"
  ) >/dev/null

  assert_file_contains "$tmp/home/.codex/config.toml" 'hooks = true'
  assert_file_contains "$tmp/home/.codex/config.toml" 'codex-for-tui-rtk-hook begin'
  assert_file_contains "$tmp/home/.codex/config.toml" 'codex-for-tui-context-hook begin'
  assert_file_contains "$tmp/home/.codex/config.toml" 'command = "codex-rtk hook"'
  assert_file_contains "$tmp/home/.codex/config.toml" 'command = "codex-context hook"'
  assert_file_contains "$tmp/home/.codex/config.toml" 'approval_policy = "never"'
  assert_file_contains "$tmp/home/.codex/config.toml" 'sandbox_mode = "danger-full-access"'
  assert_file_contains "$tmp/second.json" '"active": true'
  assert_file_contains "$tmp/second.json" '"name": "second"'
  rm -rf "$tmp"
}

test_generated_launcher_entrypoints_and_normal_path() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-launcher.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/home/.local/bin" "$tmp/bin" "$tmp/state" "$tmp/curl" "$tmp/prefix/local/bin"
  printf 'configured = true\n' > "$tmp/home/.codex/config.toml"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "codex-cli test-build"
  exit 0
fi
printf 'real-codex:%s:%s:%s:%s:%s\n' "$HOME" "$CODEX_HOME" "${CODEX_SQLITE_HOME:-}" "$PATH" "$*"
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  cat > "$tmp/prefix/local/bin/codex-preview" <<'EOF'
#!/usr/bin/env sh
printf 'bridge-preview:%s:%s\n' "$PREFIX" "$*"
EOF
  chmod +x "$tmp/prefix/local/bin/codex-preview"

  cat > "$tmp/prefix/local/bin/codex-context" <<'EOF'
#!/usr/bin/env sh
printf 'bridge-context:%s:%s\n' "$PREFIX" "$*"
EOF
  chmod +x "$tmp/prefix/local/bin/codex-context"

  cat > "$tmp/bin/codex-update" <<'EOF'
#!/usr/bin/env sh
printf 'update-ran:%s\n' "$*"
EOF
  chmod +x "$tmp/bin/codex-update"
  cp "$tmp/bin/codex-update" "$tmp/home/.local/bin/codex-update"

  PYTHONNOUSERSITE=1 python3 "$SCRIPT_DIR/libexec/codex-config-engine.py" \
    --codex-home "$tmp/home/.codex" \
    profile create \
    --name normal \
    --mode official \
    --model gpt-5.4 \
    --activate >/dev/null

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
  assert_file_contains "$tmp/bin/codex" '上下文监测'
  assert_file_contains "$tmp/bin/codex" 'codex_config_menu'
  assert_file_contains "$tmp/bin/codex" 'CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"'
  assert_file_contains "$tmp/bin/codex" 'codex_for_tui_prefix_bin'
  [ -x "$tmp/bin/codex-preview" ] || fail "codex-preview bridge wrapper was not installed"
  assert_file_not_contains "$tmp/bin/codex" '--preflight'
  assert_file_not_contains "$tmp/bin/codex" '--refresh-current-profile'
  assert_file_not_contains "$tmp/bin/codex" 'refresh-models'
  assert_file_not_contains "$tmp/bin/codex" 'AGENTS.md'

  if ! output="$(PREFIX="$tmp/prefix" "$tmp/bin/codex-preview" probe)"; then
    fail "codex-preview bridge wrapper failed"
  fi
  printf '%s\n' "$output" | grep -F "bridge-preview:$tmp/prefix:probe" >/dev/null 2>&1 || fail "codex-preview bridge wrapper did not forward to app bridge"

  if ! output="$(
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    PREFIX="$tmp/prefix" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" hello
  )"; then
    fail "normal codex launcher command failed"
  fi
  printf '%s\n' "$output" | grep -F 'real-codex:' >/dev/null 2>&1 || fail "normal codex did not run real binary"
  printf '%s\n' "$output" | grep -F '/.codex/config-runtimes/' >/dev/null 2>&1 ||
    fail "normal codex did not use an isolated profile runtime"
  printf '%s\n' "$output" | grep -F '/sqlite-builds/' >/dev/null 2>&1 ||
    fail "normal codex did not isolate SQLite by binary build"
  printf '%s\n' "$output" | grep -F 'apk-2.4.10' >/dev/null 2>&1 ||
    fail "normal codex did not include the APK runtime epoch in SQLite isolation"
  printf '%s\n' "$output" | grep -F "$tmp/prefix/local/bin" >/dev/null 2>&1 || fail "normal codex did not carry app bridge bin in PATH"
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

  if ! output="$(
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    PREFIX="$tmp/prefix" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" 上下文监测
  )"; then
    fail "codex context monitor default launcher command failed"
  fi
  printf '%s\n' "$output" | grep -F "bridge-context:$tmp/prefix:report" >/dev/null 2>&1 || fail "codex 上下文监测 did not invoke codex-context report by default"

  if ! output="$(
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    PREFIX="$tmp/prefix" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" 上下文监测 状态
  )"; then
    fail "codex context monitor launcher command failed"
  fi
  printf '%s\n' "$output" | grep -F "bridge-context:$tmp/prefix:status" >/dev/null 2>&1 || fail "codex 上下文监测 did not invoke codex-context status"

  PYTHONNOUSERSITE=1 python3 "$SCRIPT_DIR/libexec/codex-config-engine.py" \
    --codex-home "$tmp/home/.codex" \
    profile create \
    --name menu-test \
    --mode official \
    --model gpt-5.4 \
    --activate >/dev/null
  if ! printf 'b\n' |
    HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    CODEX_ZH_FORCE_STDIN=1 \
    CODEX_FOR_TUI_HOOK_AUTH_PROMPT=0 \
    CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT=0 \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" 配置模式 >"$tmp/config-mode.out" 2>"$tmp/config-mode.err"
  then
    fail "codex config mode back path failed"
  fi
  assert_file_contains "$tmp/config-mode.err" "Codex 配置模式"
  assert_file_contains "$tmp/config-mode.out" "已退出配置模式。"
  assert_file_not_contains "$tmp/config-mode.out" "real-codex:"

  printf '%s\n' '{invalid-json' > "$tmp/home/.codex/config-profiles-v2/index.json"
  set +e
  HOME="$tmp/home" \
  CODEX_HOME="$tmp/home/.codex" \
  CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
  CODEX_FOR_TUI_HOOK_AUTH_PROMPT=0 \
  CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT=0 \
  PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" should-not-run >"$tmp/corrupt.out" 2>"$tmp/corrupt.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "corrupt V2 state should block Codex startup"
  assert_file_contains "$tmp/corrupt.err" "未启动 Codex"
  assert_file_not_contains "$tmp/corrupt.out" "real-codex:"
  rm -rf "$tmp"
}

test_generated_launcher_blocks_unupgraded_v1() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-migration-failure.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/config-profiles/broken" "$tmp/bin"
  printf '%s\n' \
    'model = "gpt-5.4"' \
    'model_auto_compact_token_limit = 220000' \
    > "$tmp/home/.codex/config.toml"
  cp "$tmp/home/.codex/config.toml" \
    "$tmp/home/.codex/config-profiles/broken/config.toml"
  printf '%s\n' 'broken' > "$tmp/home/.codex/config-profiles/current"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "codex-cli migration-failure"
  exit 0
fi
printf 'real-codex-should-not-run:%s\n' "$*"
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_write_launcher
  )

  set +e
  HOME="$tmp/home" \
    CODEX_HOME="$tmp/home/.codex" \
    CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
    PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" should-not-run >"$tmp/stdout" 2>"$tmp/stderr"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "unupgraded V1 state should return a non-zero status"
  assert_file_contains "$tmp/stderr" "旧配置结构但 APK 环境升级尚未完成；未启动 Codex"
  assert_file_not_contains "$tmp/stdout" "real-codex-should-not-run:"
  assert_file_not_contains "$tmp/stderr" "real-codex-should-not-run:"
  rm -rf "$tmp"
}

test_generated_launcher_isolates_parallel_profiles() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-profile-isolation.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex/sessions" "$tmp/bin"
  log="$tmp/runs.log"
  release="$tmp/release-first"
  printf '%s\n' 'sqlite_home = "/tmp/shared-old-sqlite"' > "$tmp/home/.codex/config.toml"
  printf '%s\n' '{"session":"must-not-be-shared"}' > "$tmp/home/.codex/sessions/control.jsonl"
  printf '%s\n' '{"history":"must-not-be-shared"}' > "$tmp/home/.codex/history.jsonl"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "codex-cli profile-isolation"
  exit 0
fi
model="$(sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CODEX_HOME/config.toml" | sed -n '1p')"
config_sqlite="$(sed -n 's/^[[:space:]]*sqlite_home[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CODEX_HOME/config.toml" | sed -n '1p')"
base_url="$(sed -n 's/^[[:space:]]*base_url[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CODEX_HOME/config.toml" | sed -n '1p')"
printf '%s|%s|%s|%s|%s\n' "$CODEX_HOME" "${CODEX_SQLITE_HOME:-}" "$model" "$config_sqlite" "$base_url" >> "$CODEX_TEST_LOG"
if [ "${1:-}" = "hold" ]; then
  while [ ! -e "$CODEX_TEST_RELEASE" ]; do
    sleep 0.1
  done
fi
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  PYTHONNOUSERSITE=1 python3 "$SCRIPT_DIR/libexec/codex-config-engine.py" \
    --codex-home "$tmp/home/.codex" \
    profile create \
    --name alpha \
    --mode third_party \
    --provider-name Alpha \
    --base-url https://alpha.example.test/v1 \
    --model gpt-5.4 \
    --activate >/dev/null
  PYTHONNOUSERSITE=1 python3 "$SCRIPT_DIR/libexec/codex-config-engine.py" \
    --codex-home "$tmp/home/.codex" \
    profile create \
    --name beta \
    --mode third_party \
    --provider-name Beta \
    --base-url https://beta.example.test/v1 \
    --model gpt-5.5 >/dev/null

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    export CODEX_ZH_INSTALL_DIR="$tmp/bin"
    codex_local_write_launcher
  )

  HOME="$tmp/home" \
  CODEX_HOME="$tmp/home/.codex" \
  CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
  CODEX_FOR_TUI_HOOK_AUTH_PROMPT=0 \
  CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT=0 \
  CODEX_TEST_LOG="$log" \
  CODEX_TEST_RELEASE="$release" \
  PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" hold &
  first_pid=$!

  attempts=0
  while [ ! -s "$log" ] && [ "$attempts" -lt 100 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
  done
  [ -s "$log" ] || {
    kill "$first_pid" 2>/dev/null || true
    fail "first isolated profile did not start"
  }

  PYTHONNOUSERSITE=1 python3 "$SCRIPT_DIR/libexec/codex-config-engine.py" \
    --codex-home "$tmp/home/.codex" \
    profile activate beta >/dev/null
  HOME="$tmp/home" \
  CODEX_HOME="$tmp/home/.codex" \
  CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
  CODEX_FOR_TUI_HOOK_AUTH_PROMPT=0 \
  CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT=0 \
  CODEX_TEST_LOG="$log" \
  CODEX_TEST_RELEASE="$release" \
  PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" second

  kill -0 "$first_pid" 2>/dev/null || fail "starting beta terminated the live alpha session"
  printf '%s\n' '# same version, different localized build' >> "$tmp/bin/codex-zh-bin"
  HOME="$tmp/home" \
  CODEX_HOME="$tmp/home/.codex" \
  CODEX_ZH_SCRIPT_INSTALL_ROOT="$SCRIPT_DIR" \
  CODEX_FOR_TUI_HOOK_AUTH_PROMPT=0 \
  CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT=0 \
  CODEX_TEST_LOG="$log" \
  CODEX_TEST_RELEASE="$release" \
  PATH="$tmp/bin:/bin:/usr/bin" \
    "$tmp/bin/codex" rebuilt
  kill -0 "$first_pid" 2>/dev/null ||
    fail "starting a rebuilt binary terminated the older live session"

  first_runtime="$(sed -n '1p' "$log" | cut -d '|' -f 1)"
  first_sqlite="$(sed -n '1p' "$log" | cut -d '|' -f 2)"
  first_model="$(sed -n '1p' "$log" | cut -d '|' -f 3)"
  second_runtime="$(sed -n '2p' "$log" | cut -d '|' -f 1)"
  second_sqlite="$(sed -n '2p' "$log" | cut -d '|' -f 2)"
  second_model="$(sed -n '2p' "$log" | cut -d '|' -f 3)"
  third_runtime="$(sed -n '3p' "$log" | cut -d '|' -f 1)"
  third_sqlite="$(sed -n '3p' "$log" | cut -d '|' -f 2)"
  first_config_sqlite="$(sed -n '1p' "$log" | cut -d '|' -f 4)"
  second_config_sqlite="$(sed -n '2p' "$log" | cut -d '|' -f 4)"
  third_config_sqlite="$(sed -n '3p' "$log" | cut -d '|' -f 4)"
  first_base_url="$(sed -n '1p' "$log" | cut -d '|' -f 5)"
  second_base_url="$(sed -n '2p' "$log" | cut -d '|' -f 5)"
  [ "$first_runtime" != "$second_runtime" ] || fail "different profiles shared one runtime home"
  [ "$first_sqlite" != "$second_sqlite" ] || fail "different profiles shared one SQLite home"
  [ "$second_runtime" = "$third_runtime" ] || fail "one profile changed runtime home after a rebuild"
  [ "$second_sqlite" != "$third_sqlite" ] ||
    fail "same-version rebuilt binaries reused one SQLx migration database"
  [ "$first_model" = "gpt-5.4" ] || fail "alpha launched with the wrong model"
  [ "$second_model" = "gpt-5.5" ] || fail "beta launched with the wrong model"
  [ "$first_base_url" = "https://alpha.example.test/v1" ] ||
    fail "alpha launched against the wrong provider site"
  [ "$second_base_url" = "https://beta.example.test/v1" ] ||
    fail "beta launched against the wrong provider site"
  [ "$first_config_sqlite" = "$first_sqlite" ] ||
    fail "alpha config.toml overrode the build-isolated SQLite home"
  [ "$second_config_sqlite" = "$second_sqlite" ] ||
    fail "beta config.toml overrode the build-isolated SQLite home"
  [ "$third_config_sqlite" = "$third_sqlite" ] ||
    fail "rebuilt config.toml reused the previous SQLx migration database"
  [ ! -L "$first_runtime/sessions" ] || fail "alpha runtime symlinked shared sessions"
  [ ! -L "$first_runtime/history.jsonl" ] || fail "alpha runtime symlinked shared history"
  [ ! -e "$first_runtime/sessions/control.jsonl" ] ||
    fail "alpha runtime inherited control-home session data"
  [ ! -L "$second_runtime/sessions" ] || fail "beta runtime symlinked shared sessions"
  [ ! -e "$second_runtime/sessions/control.jsonl" ] ||
    fail "beta runtime inherited control-home session data"
  assert_file_contains "$first_runtime/config.toml" 'model = "gpt-5.4"'
  assert_file_contains "$first_runtime/config.toml" 'base_url = "https://alpha.example.test/v1"'
  assert_file_contains "$second_runtime/config.toml" 'model = "gpt-5.5"'
  assert_file_contains "$second_runtime/config.toml" 'base_url = "https://beta.example.test/v1"'

  : > "$release"
  wait "$first_pid"
  assert_file_contains "$tmp/home/.codex/config.toml" 'model = "gpt-5.5"'
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

test_update_apply_installs_self_test_script_and_aliases() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-update-self-test.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/bin" "$tmp/share"

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
      printf '#!/usr/bin/env sh\nprintf "fetched:%s\\n"\n' "$stub_rel" > "$stub_dest"
      chmod 755 "$stub_dest"
      return 0
    }
    codex_update_apply 0 >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "codex update apply should install self-test script"
  }

  [ -s "$tmp/share/codex-for-tui-self-test.sh" ] || fail "self-test script was not installed into script share"
  [ -x "$tmp/bin/codex-self-test" ] || fail "codex-self-test alias was not installed"
  [ -x "$tmp/bin/codex-test" ] || fail "codex-test alias was not installed"
  [ -x "$tmp/bin/codex-preview" ] || fail "codex-preview bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-browser" ] || fail "codex-browser bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-panel" ] || fail "codex-panel bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-session" ] || fail "codex-session bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-rtk" ] || fail "codex-rtk bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-context" ] || fail "codex-context bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-doctor" ] || fail "codex-doctor bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-clean" ] || fail "codex-clean bridge wrapper was not installed by update"
  [ -x "$tmp/bin/codex-ops" ] || fail "codex-ops bridge wrapper was not installed by update"
  assert_file_contains "$tmp/stdout" "已更新：codex-for-tui-self-test.sh"
  rm -rf "$tmp"
}

test_update_self_test_subcommand_fetches_and_runs_script() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-run-self-test.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home" "$tmp/bin" "$tmp/share"

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
      {
        printf '%s\n' '#!/usr/bin/env sh'
        printf '%s\n' 'printf "self-test-ran:%s:%s\n" "$HOME" "$1"'
      } > "$stub_dest"
      chmod 755 "$stub_dest"
      return 0
    }
    codex_update_run_self_test probe >"$tmp/stdout" 2>"$tmp/stderr"
  ) || {
    sed -n '1,200p' "$tmp/stderr" >&2 || true
    fail "codex update self-test command should fetch and run self-test script"
  }

  assert_file_contains "$tmp/stdout" "self-test-ran:$tmp/home:probe"
  [ -x "$tmp/bin/codex-self-test" ] || fail "self-test command alias was not installed after on-demand fetch"
  rm -rf "$tmp"
}

test_codex_local_profile_commands_are_explicit_only() {
  assert_file_contains "$SCRIPT_DIR/codex-local-resume.sh" 'profile-new'
  assert_file_contains "$SCRIPT_DIR/codex-local-resume.sh" 'profile-save'
  assert_file_contains "$SCRIPT_DIR/codex-local-resume.sh" 'profile-use'
  assert_file_contains "$SCRIPT_DIR/codex-local-resume.sh" 'profile-list'
  assert_file_contains "$SCRIPT_DIR/codex-local-resume.sh" 'codex_config_menu'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_v2_choose_profile'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_v2_dirty_guard'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_repair_full_permission'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'sandbox_mode = \"danger-full-access\"'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_write_model_catalog'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_write_third_party_config'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'context_window": 272000'
  assert_file_not_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'openai/codex/main'
  assert_file_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'slug.startswith("codex-auto-")'
  assert_file_contains "$SCRIPT_DIR/libexec/codex-config-engine.py" 'model["visibility"] = "hide"'
  assert_file_contains "$SCRIPT_DIR/data/openai-models-source.json" '"source_ref": "rust-v0.144.1"'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'elif command -v openssl'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" '无法计算 Codex 二进制 SHA-256'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'wc -c < "$real_bin"'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-update.sh" 'codex_local_install_binary'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-update.sh" 'codex-zh-bin'
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'profile-use'
}

test_installer_does_not_manage_agents_md() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-no-agents.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home"

  (
    . "$SCRIPT_DIR/lib/codex-zh-common.sh"
    . "$SCRIPT_DIR/lib/codex-zh-local.sh"
    export HOME="$tmp/home"
    export CODEX_HOME="$tmp/home/.codex"
    codex_local_setup_agents
  )

  [ ! -e "$tmp/home/.codex/AGENTS.md" ] || fail "installer should not create AGENTS.md"
  assert_file_not_contains "$SCRIPT_DIR/lib/codex-zh-local.sh" 'missing_agents'
  rm -rf "$tmp"
}

run_step test_android_session_uses_root_codex_home
run_step test_android_lifecycle_rootfs_guards
run_step test_bootstrap_asset_is_synced
run_step test_apk_upgrade_guards
run_step test_debug_build_uses_test_package_name
run_step test_release_workflow_signature_gate
run_step test_android_security_guards
run_step test_terminal_performance_guards
run_step test_image_preview_bridge_asset
run_step test_codex_ops_tool_assets
run_step test_browser_bridge_asset
run_step test_browser_background_asset
run_step test_agent_panel_bridge_asset
run_step test_session_fold_bridge_asset
run_step test_codex_rtk_bridge_asset
run_step test_codex_context_bridge_asset
run_step test_codex_config_default_hooks_survive_profile_use
run_step test_generated_launcher_entrypoints_and_normal_path
run_step test_generated_launcher_blocks_unupgraded_v1
run_step test_generated_launcher_isolates_parallel_profiles
run_step test_generated_launcher_first_run_configures_then_runs
run_step test_update_apply_installs_self_test_script_and_aliases
run_step test_update_self_test_subcommand_fetches_and_runs_script
run_step test_codex_local_profile_commands_are_explicit_only
run_step test_installer_does_not_manage_agents_md
printf 'OK: Codex for TUI static guards passed\n'
