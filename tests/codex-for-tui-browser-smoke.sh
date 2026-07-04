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

run_browser open "$base/index.html"
run_browser get-text '#ready' | grep -F 'state=done' >/dev/null || fail "get-text did not complete"
run_browser cookies verify "$base/index.html" | grep -F 'verified=1' >/dev/null || fail "cookie verification failed"
run_browser js "localStorage.getItem('codex_smoke_storage')" | grep -F 'state=done' >/dev/null || fail "localStorage js read failed"

run_browser new-tab "$base/page2.html" | grep -F 'state=done' >/dev/null || fail "new-tab failed"
run_browser list-tabs | grep -F 'tabs_count=' >/dev/null || fail "list-tabs did not return status"
run_browser select-tab 1 | grep -F 'state=done' >/dev/null || fail "select-tab failed"

i=1
while [ "$i" -le 20 ]; do
  codex-browser --no-wait js "return 'queue-$i';" >/dev/null
  i=$((i + 1))
done
sleep 3
codex-browser status | grep -F 'ok=1' >/dev/null || fail "queued browser commands did not leave ok status"

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
codex-browser --no-wait user-wait 'smoke user handoff' >/dev/null
sleep 1
codex-browser status | grep -F 'needs_user=1' >/dev/null || fail "user-wait did not set needs_user"
run_browser user-done | grep -F 'needs_user=0' >/dev/null || fail "user-done did not clear needs_user"

printf 'OK: browser smoke passed\n'
