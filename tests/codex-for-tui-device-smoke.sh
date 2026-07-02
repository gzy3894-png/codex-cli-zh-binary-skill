#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ADB="${ADB:-adb}"
APK="${CODEX_TUI_APK:-$ROOT_DIR/android-app/app/build/outputs/apk/debug/app-debug.apk}"
PACKAGE="${CODEX_TUI_PACKAGE:-com.gzy3894.codexfortui.debug}"
ACTIVITY="${CODEX_TUI_ACTIVITY:-com.rk.terminal.ui.activities.terminal.MainActivity}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'INFO: %s\n' "$*" >&2
}

[ -f "$APK" ] || fail "APK not found: $APK"
command -v "$ADB" >/dev/null 2>&1 || fail "adb not found: $ADB"

wait_seconds="${CODEX_TUI_ADB_WAIT_SECONDS:-120}"
elapsed=0
state=""
while [ "$elapsed" -lt "$wait_seconds" ]; do
  state="$("$ADB" get-state 2>/dev/null | tr -d '\r' | sed -n '1p' || true)"
  [ "$state" = "device" ] && break
  sleep 2
  elapsed=$((elapsed + 2))
done
[ "$state" = "device" ] || fail "no adb device became ready within ${wait_seconds}s"

boot="$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | sed -n '1p')"
[ "$boot" = "1" ] || fail "device is not fully booted (sys.boot_completed=$boot)"

info "installing $APK"
"$ADB" install -r "$APK" >/dev/null

if [ "${CODEX_TUI_CLEAR_DATA:-0}" = "1" ]; then
  info "clearing app data for $PACKAGE"
  "$ADB" shell pm clear "$PACKAGE" >/dev/null
fi

info "launching $PACKAGE/$ACTIVITY"
"$ADB" shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null
sleep "${CODEX_TUI_LAUNCH_WAIT_SECONDS:-8}"

pid="$("$ADB" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' | sed -n '1p')"
[ -n "$pid" ] || fail "app process is not running after launch"

if "$ADB" shell run-as "$PACKAGE" pwd >/dev/null 2>&1; then
  legacy_path="local/alpine/sdcard/.codex"
  if "$ADB" shell run-as "$PACKAGE" sh -c "test -e '$legacy_path'" >/dev/null 2>&1; then
    fail "legacy sdcard CODEX_HOME exists in app private data: $legacy_path"
  fi
  info "run-as check passed: no legacy local/alpine/sdcard/.codex"
else
  info "run-as unavailable for $PACKAGE; skipping private-data sdcard check"
fi

cat <<'EOF'
MANUAL TERMINAL ASSERTIONS:
1. echo $HOME            -> /root
2. echo $CODEX_HOME      -> /root/.codex
3. codex                -> if config/auth is missing, opens the config guide once, then runs Codex
4. codex 配置模式        -> opens the config guide explicitly
5. codex 更新            -> runs codex-update apply
EOF

printf 'OK: Codex for TUI device smoke launch passed\n'
