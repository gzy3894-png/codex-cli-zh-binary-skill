#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/android-arm64-musl"
BUILD_WORKFLOW="$ROOT_DIR/.github/workflows/build-codex-for-tui.yml"
MKSESSION="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MkSession.kt"
INIT_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/init.sh"
APP_BUILD_GRADLE="$ROOT_DIR/android-app/app/build.gradle.kts"
BOOTSTRAP="$SCRIPT_DIR/codex-for-tui-bootstrap.sh"
BOOTSTRAP_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh"
PREVIEW_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-preview"
PUSH_IMAGE_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-push-image"
PUSH_MEDIA_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-push-media"
BROWSER_ASSET="$ROOT_DIR/android-app/core/main/src/main/assets/codex-browser"
TERMINAL_TOP_BAR="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalTopBar.kt"
MEDIA_PREVIEW_PANE="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/MediaPreviewPane.kt"
MAIN_ACTIVITY="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/activities/terminal/MainActivity.kt"
BROWSER_PANEL_PANE="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/BrowserPanelPane.kt"
TERMINAL_BROWSER_SESSION="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalBrowserSession.kt"
TERMINAL_VIEW_MODEL="$ROOT_DIR/android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalViewModel.kt"

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

run_step() {
  name="$1"
  printf 'RUN %s\n' "$name"
  "$name"
}

test_android_session_uses_root_codex_home() {
  assert_file_not_contains "$MKSESSION" 'HOME=/sdcard'
  assert_file_contains "$MKSESSION" 'HOME=/root'
  assert_file_contains "$MKSESSION" 'CODEX_HOME=/root/.codex'
  assert_file_contains "$INIT_ASSET" 'export HOME="${HOME:-/root}"'
  assert_file_contains "$INIT_ASSET" 'export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"'
}

test_bootstrap_asset_is_synced() {
  cmp "$BOOTSTRAP" "$BOOTSTRAP_ASSET" >/dev/null 2>&1 || fail "bootstrap source and APK asset differ"
}

test_debug_build_uses_test_package_name() {
  assert_file_contains "$APP_BUILD_GRADLE" 'applicationIdSuffix = ".test"'
  assert_file_contains "$APP_BUILD_GRADLE" 'versionNameSuffix = "-TEST"'
  assert_file_contains "$APP_BUILD_GRADLE" 'Codex for TUI Test'
  assert_file_contains "$APP_BUILD_GRADLE" 'versionCode = 23'
  assert_file_contains "$APP_BUILD_GRADLE" 'versionName = "2.0.3"'
}

test_release_workflow_signature_gate() {
  assert_file_contains "$BUILD_WORKFLOW" 'CODEX_TUI_RELEASE_CERT_SHA256: a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc'
  assert_file_contains "$BUILD_WORKFLOW" 'name: Verify release APK signature'
  assert_file_contains "$BUILD_WORKFLOW" 'apksigner" verify --print-certs "$apk"'
  assert_file_contains "$BUILD_WORKFLOW" 'Signer #1 certificate SHA-256 digest:'
  assert_file_contains "$BUILD_WORKFLOW" 'Release APK signing certificate mismatch'
  assert_file_contains "$BUILD_WORKFLOW" 'artifact_name=codex-for-tui-release-apk'
  assert_file_not_contains "$BUILD_WORKFLOW" 'codex-for-tui-unsigned-or-test-signed-release-apk'
}

test_image_preview_bridge_asset() {
  assert_file_contains "$MKSESSION" '"codex-preview" to "codex-preview"'
  assert_file_contains "$MKSESSION" '"codex-push-image" to "codex-push-image"'
  assert_file_contains "$MKSESSION" '"codex-push-media" to "codex-push-media"'
  assert_file_contains "$MKSESSION" '"codex-browser" to "codex-browser"'
  assert_file_contains "$INIT_ASSET" 'ensure_codex_preview'
  assert_file_contains "$INIT_ASSET" '[ ! -r /etc/profile ] || . /etc/profile'
  assert_file_contains "$INIT_ASSET" 'export PATH="${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin:$PATH"'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'EmptyPreviewTray'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'GridCells.Adaptive'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'TextComposerTile'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'onSendText'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'text = if (previewCount <= 0) "文件"'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'Text("发送")'
  assert_file_contains "$MEDIA_PREVIEW_PANE" '附加说明（可选）'
  assert_file_contains "$MEDIA_PREVIEW_PANE" '.height(28.dp)'
  assert_file_contains "$MEDIA_PREVIEW_PANE" 'color = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f)'
  assert_file_contains "$BROWSER_PANEL_PANE" '.height(28.dp)'
  assert_file_contains "$BROWSER_PANEL_PANE" 'BrowserTabChip'
  assert_file_contains "$BROWSER_PANEL_PANE" 'onSelectTab = browserSessionManager::selectTabFromUi'
  assert_file_contains "$BROWSER_PANEL_PANE" 'color = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f)'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'fun selectTabFromUi'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'fun closeTabFromUi'
  assert_file_contains "$MAIN_ACTIVITY" 'codex-preview path'
  assert_file_contains "$MAIN_ACTIVITY" 'writePreviewReference'
  assert_file_contains "$MAIN_ACTIVITY" 'sendComposerTextToAi'
  assert_file_contains "$MAIN_ACTIVITY" 'writeAgentPanelEvent'
  assert_file_contains "$MAIN_ACTIVITY" 'private fun syncMediaPreviewStatus'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "top_bar", state = "ready")'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "collapse", state = "done")'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "delete_item", state = "ready")'
  assert_file_contains "$MAIN_ACTIVITY" 'syncMediaPreviewStatus(reason = "composer_sent", state = "done")'
  assert_file_contains "$MAIN_ACTIVITY" 'user_sent_text'
  assert_file_contains "$MAIN_ACTIVITY" 'visible='
  assert_file_contains "$MAIN_ACTIVITY" 'collapsed='
  assert_file_not_contains "$MAIN_ACTIVITY" '不要让我粘贴全文'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview path FILE_ID'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview [--present|--background] text --stdin'
  assert_file_contains "$PREVIEW_ASSET" 'codex-preview status|events|wait|close'
  assert_file_contains "$PREVIEW_ASSET" 'present=%s'
  assert_file_contains "$INIT_ASSET" 'codex-preview path FILE_ID'
  assert_file_contains "$INIT_ASSET" '[ -x "$bin_dir/codex-preview" ]'
  assert_file_contains "$INIT_ASSET" 'codex-preview [--present|--background] text --stdin'
  assert_file_contains "$TERMINAL_VIEW_MODEL" 'fun addMediaPreview'
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
  sh -n "$INIT_ASSET" || fail "init.sh shell syntax failed"

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

  if ! output="$(PREFIX="$tmp/prefix" sh "$PREVIEW_ASSET" close)"; then
    fail "codex-preview close should write a clear request"
  fi
  assert_file_contains "$tmp/prefix/local/media-preview/request" "action=clear"
  printf '%s\n' "$output" | grep -F '已清空 Codex for TUI 文件面板' >/dev/null 2>&1 || fail "preview close did not report success"
  rm -rf "$tmp"
}

test_browser_bridge_asset() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-browser.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/prefix"

  if ! output="$(PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait open https://example.test)"; then
    fail "codex-browser should write an open request"
  fi
  [ -s "$tmp/prefix/local/browser/request" ] || fail "browser request file missing"
  assert_file_contains "$tmp/prefix/local/browser/request" "action=navigate"
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

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait auth https://login.example.test >/dev/null; then
    fail "codex-browser should write an auth request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=auth"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://login.example.test"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait external https://external.example.test >/dev/null; then
    fail "codex-browser should write an external request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=external"
  assert_file_contains "$tmp/prefix/local/browser/request" "url=https://external.example.test"

  if ! PREFIX="$tmp/prefix" sh "$BROWSER_ASSET" --no-wait type '#q' 'hello world' >/dev/null; then
    fail "codex-browser should write a type request"
  fi
  assert_file_contains "$tmp/prefix/local/browser/request" "action=type"
  assert_file_contains "$tmp/prefix/local/browser/request" "selector=#q"
  assert_file_contains "$tmp/prefix/local/browser/request" "text=hello world"

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
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'CustomTabsIntent.Builder'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'shouldHandleOutsideWebView'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'onShowFileChooser'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" '"present" -> present'
  assert_file_contains "$TERMINAL_BROWSER_SESSION" 'activeUserRequestId'
  assert_file_contains "$MAIN_ACTIVITY" 'action == "present"'
  assert_file_contains "$MAIN_ACTIVITY" 'snapshot?.optBoolean("needsUser") == true'
  assert_file_contains "$MAIN_ACTIVITY" 'val shouldCollapse = action == "user_done" || action == "user_cancelled"'
  assert_file_contains "$MAIN_ACTIVITY" 'markBrowserUserDone(reason = "user_collapsed")'
  rm -rf "$tmp"
}

test_generated_launcher_entrypoints_and_normal_path() {
  tmp="${TMPDIR:-/tmp}/codex-tui-static-launcher.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp/home/.codex" "$tmp/home/.local/bin" "$tmp/bin" "$tmp/state" "$tmp/curl" "$tmp/prefix/local/bin"
  printf 'configured = true\n' > "$tmp/home/.codex/config.toml"

  cat > "$tmp/bin/codex-zh-bin" <<'EOF'
#!/usr/bin/env sh
printf 'real-codex:%s:%s:%s:%s\n' "$HOME" "$CODEX_HOME" "$PATH" "$*"
EOF
  chmod +x "$tmp/bin/codex-zh-bin"

  cat > "$tmp/prefix/local/bin/codex-preview" <<'EOF'
#!/usr/bin/env sh
printf 'bridge-preview:%s:%s\n' "$PREFIX" "$*"
EOF
  chmod +x "$tmp/prefix/local/bin/codex-preview"

  cat > "$tmp/bin/codex-update" <<'EOF'
#!/usr/bin/env sh
printf 'update-ran:%s\n' "$*"
EOF
  chmod +x "$tmp/bin/codex-update"
  cp "$tmp/bin/codex-update" "$tmp/home/.local/bin/codex-update"

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
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_profile_choose_use'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'codex_config_repair_full_permission'
  assert_file_contains "$SCRIPT_DIR/lib/codex-zh-config.sh" 'sandbox_mode = \"danger-full-access\"'
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
run_step test_bootstrap_asset_is_synced
run_step test_debug_build_uses_test_package_name
run_step test_release_workflow_signature_gate
run_step test_image_preview_bridge_asset
run_step test_browser_bridge_asset
run_step test_generated_launcher_entrypoints_and_normal_path
run_step test_generated_launcher_first_run_configures_then_runs
run_step test_update_apply_installs_self_test_script_and_aliases
run_step test_update_self_test_subcommand_fetches_and_runs_script
run_step test_codex_local_profile_commands_are_explicit_only
run_step test_installer_does_not_manage_agents_md
printf 'OK: Codex for TUI static guards passed\n'
