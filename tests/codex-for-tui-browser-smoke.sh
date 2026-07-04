#!/usr/bin/env sh
set -eu

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'INFO: %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

http_get() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "$url" >/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null "$url"
  else
    fail "missing curl or wget"
  fi
}

run_browser() {
  info "codex-browser $*"
  codex-browser "$@"
}

send_browser_no_wait() {
  info "codex-browser --no-wait $*"
  output="$(codex-browser --no-wait "$@")" || fail "codex-browser --no-wait failed: $*"
  request_id="$(printf '%s\n' "$output" | sed -n 's/^已发送到 Codex for TUI 浏览器: //p' | sed -n '1p')"
  [ -n "$request_id" ] || fail "missing request id for: $*"
  printf '%s\n' "$request_id"
}

wait_browser_result_contains() {
  request_id="$1"
  needle="$2"
  elapsed=0
  while [ "$elapsed" -lt 30 ]; do
    result="$(codex-browser result "$request_id" 2>/dev/null || true)"
    if printf '%s\n' "$result" | grep -F '"ok": true' >/dev/null 2>&1 &&
      printf '%s\n' "$result" | grep -F "$needle" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  printf '%s\n' "$result" >&2
  fail "browser result $request_id did not contain: $needle"
}

browser_event_count() {
  codex-browser events 2>/dev/null | wc -l | tr -d ' '
}

wait_browser_event_after() {
  start_line="$1"
  needle="$2"
  elapsed=0
  while [ "$elapsed" -lt 30 ]; do
    events="$(codex-browser events 2>/dev/null || true)"
    if printf '%s\n' "$events" | awk -v start="$start_line" 'NR > start { print }' | grep -F "$needle" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  printf '%s\n' "$events" >&2
  fail "browser events after line $start_line did not contain: $needle"
}

need_cmd codex-browser
need_cmd codex-preview

tmp="${TMPDIR:-/tmp}/codex-browser-smoke.$$"
webroot="$tmp/www"
mkdir -p "$webroot"

cat > "$webroot/index.html" <<'HTML'
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Codex Browser Smoke</title></head>
  <body>
    <main id="ready">Codex Browser Smoke Ready</main>
    <input id="q" value="">
    <button id="btn" onclick="document.body.dataset.clicked='1'">Click</button>
    <script>
      document.cookie = 'codex_smoke_cookie=ok; path=/; max-age=86400; SameSite=Lax';
      localStorage.setItem('codex_smoke_storage', 'ok');
    </script>
  </body>
</html>
HTML

cat > "$webroot/page2.html" <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Codex Smoke Page 2</title></head>
<body><main id="page2">Second Tab Ready</main></body></html>
HTML

cat > "$webroot/persist.html" <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Codex Smoke Persist</title></head>
<body><main id="persist-ready">Persistence Check Ready</main></body></html>
HTML

cat > "$webroot/userscript.html" <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Userscript Target</title></head>
<body><main id="target">Userscript Target</main></body></html>
HTML

cat > "$tmp/userscript.js" <<'JS'
var marker = document.createElement('div');
marker.id = 'userscript-ok';
marker.textContent = 'Userscript Injected';
document.body.appendChild(marker);
JS

port="${CODEX_BROWSER_SMOKE_PORT:-18765}"
server_pid=""
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

if command -v python3 >/dev/null 2>&1; then
  (cd "$webroot" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
  server_pid="$!"
elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -x httpd >/dev/null 2>&1; then
  busybox httpd -f -p "127.0.0.1:$port" -h "$webroot" >/dev/null 2>&1 &
  server_pid="$!"
else
  fail "missing python3 or busybox httpd for local smoke server"
fi

base="http://127.0.0.1:$port"
elapsed=0
while [ "$elapsed" -lt 20 ]; do
  if http_get "$base/index.html"; then
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
http_get "$base/index.html" || fail "local smoke server did not become reachable"

codex-browser --no-wait close >/dev/null 2>&1 || true
sleep 1

open_output="$(run_browser open "$base/index.html")"
printf '%s\n' "$open_output"
first_tab_id="$(printf '%s\n' "$open_output" | sed -n 's/^tab_id=//p' | sed -n '1p')"
[ -n "$first_tab_id" ] || fail "initial browser tab id missing"
run_browser get-text '#ready' | grep -F 'state=done' >/dev/null || fail "get-text did not complete"
run_browser cookies verify "$base/index.html" | grep -F 'verified=1' >/dev/null || fail "cookie verification failed"
storage_request="$(send_browser_no_wait js "return localStorage.getItem('codex_smoke_storage');")"
wait_browser_result_contains "$storage_request" '"value": "ok"'

events_start="$(browser_event_count)"
present_output="$(run_browser present smoke_present)"
printf '%s\n' "$present_output" | grep -F 'state=ready' >/dev/null || fail "present did not report ready"
printf '%s\n' "$present_output" | grep -F 'visible=1' >/dev/null || fail "present did not report visible=1"
printf '%s\n' "$present_output" | grep -F 'collapsed=0' >/dev/null || fail "present did not report collapsed=0"
wait_browser_event_after "$events_start" 'type=agent_presented'

events_start="$(browser_event_count)"
collapse_output="$(run_browser collapse smoke_collapse)"
printf '%s\n' "$collapse_output" | grep -F 'state=done' >/dev/null || fail "collapse did not report done"
printf '%s\n' "$collapse_output" | grep -F 'visible=0' >/dev/null || fail "collapse did not report visible=0"
printf '%s\n' "$collapse_output" | grep -F 'collapsed=1' >/dev/null || fail "collapse did not report collapsed=1"
wait_browser_event_after "$events_start" 'type=agent_collapsed'

run_browser new-tab "$base/page2.html" | grep -F 'state=done' >/dev/null || fail "new-tab failed"
run_browser list-tabs | grep -F 'tabs_count=' >/dev/null || fail "list-tabs did not return status"
run_browser select-tab "$first_tab_id" | grep -F 'state=done' >/dev/null || fail "select-tab failed"

i=1
queue_ids="$tmp/queue-ids"
: > "$queue_ids"
while [ "$i" -le 20 ]; do
  request_id="$(send_browser_no_wait js "return 'queue-$i';")"
  printf '%s %s\n' "$request_id" "queue-$i" >> "$queue_ids"
  i=$((i + 1))
done
while IFS=' ' read -r request_id expected; do
  wait_browser_result_contains "$request_id" "\"value\": \"$expected\""
done < "$queue_ids"

run_browser close | grep -F 'state=closed' >/dev/null || fail "close did not report closed"
run_browser open "$base/persist.html"
run_browser get-text '#persist-ready' | grep -F 'state=done' >/dev/null || fail "persist page did not load after browser restart"
run_browser cookies verify "$base/persist.html" | grep -F 'verified=1' >/dev/null || fail "cookie was not reused after browser restart"
storage_restart_request="$(send_browser_no_wait js "return localStorage.getItem('codex_smoke_storage');")"
wait_browser_result_contains "$storage_restart_request" '"value": "ok"'

run_browser screenshot --push --background | grep -F 'file_id=' >/dev/null || fail "screenshot --push did not return file_id"
file_id="$(codex-browser status | sed -n 's/^file_id=//p' | sed -n '1p')"
[ -n "$file_id" ] || fail "screenshot file_id missing"
preview_path="$(codex-preview path "$file_id")" || fail "codex-preview path could not resolve browser screenshot"
[ -s "$preview_path" ] || fail "browser screenshot file is empty: $preview_path"

run_browser userscript add smoke-script "127.0.0.1:$port" "$tmp/userscript.js" | grep -F 'state=done' >/dev/null || fail "userscript add failed"
run_browser open "$base/userscript.html"
run_browser get-text '#userscript-ok' | grep -F 'state=done' >/dev/null || fail "userscript marker not readable"

run_browser history | grep -F 'state=done' >/dev/null || fail "history failed"
run_browser clear-history | grep -F 'state=done' >/dev/null || fail "clear-history failed"
events_start="$(browser_event_count)"
codex-browser --no-wait user-wait 'smoke user handoff' >/dev/null
sleep 1
codex-browser status | grep -F 'needs_user=1' >/dev/null || fail "user-wait did not set needs_user"
wait_browser_event_after "$events_start" 'type=agent_user_wait'
events_start="$(browser_event_count)"
run_browser user-done | grep -F 'needs_user=0' >/dev/null || fail "user-done did not clear needs_user"
wait_browser_event_after "$events_start" 'type=agent_done'

printf 'OK: browser smoke passed\n'
