#!/usr/bin/env sh
# Local PTY smoke for codex-config-select.py — must pass before APK release.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SELECT_PY="$ROOT_DIR/android-arm64-musl/libexec/codex-config-select.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-select-pty.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -x "$SELECT_PY" ] || chmod +x "$SELECT_PY" || true
[ -f "$SELECT_PY" ] || fail "missing $SELECT_PY"

cat > "$TMP/items.txt" <<'EOF'
alpha|Alpha station
beta|Beta station
gamma|Gamma station
done|完成并退出
EOF

run_keys() {
  name="$1"
  keys_py="$2"
  expect_rc="$3"
  expect_out="$4"
  python3 - "$SELECT_PY" "$TMP/items.txt" "$TMP/out.$name" "$keys_py" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

select_py, items, out_path, keys_spec = sys.argv[1:5]
# keys_spec is a python literal list of bytes chunks
keys = eval(keys_spec, {"__builtins__": {}})

master, slave = pty.openpty()
env = os.environ.copy()
env["TERM"] = "xterm-256color"
proc = subprocess.Popen(
    [sys.executable, select_py, "--title", "PTY test hub", "--file", items, "--default", "1", "--tty", os.ttyname(slave)],
    stdin=slave,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
    close_fds=True,
)
os.close(slave)

# Give the picker a moment to set cbreak and render
time.sleep(0.15)

for chunk in keys:
    if isinstance(chunk, str):
        chunk = chunk.encode("latin1")
    os.write(master, chunk)
    time.sleep(0.05)

# Drain with timeout
deadline = time.time() + 3.0
stdout = b""
stderr = b""
while time.time() < deadline:
    if proc.poll() is not None:
        break
    r, _, _ = select.select([master], [], [], 0.05)
    if r:
        try:
            os.read(master, 4096)
        except OSError:
            break
rc = proc.wait(timeout=2)
stdout = proc.stdout.read() if proc.stdout else b""
stderr = proc.stderr.read() if proc.stderr else b""
os.close(master)
open(out_path + ".rc", "w", encoding="utf-8").write(str(rc))
open(out_path + ".out", "wb").write(stdout)
open(out_path + ".err", "wb").write(stderr)
print(rc, stdout.decode("utf-8", "replace").strip())
PY
  rc="$(cat "$TMP/out.$name.rc")"
  out="$(cat "$TMP/out.$name.out")"
  err="$(cat "$TMP/out.$name.err" 2>/dev/null || true)"
  [ "$rc" = "$expect_rc" ] || fail "$name: rc=$rc expected $expect_rc out=[$out] err=[$err]"
  if [ -n "$expect_out" ]; then
    printf '%s' "$out" | grep -F -- "$expect_out" >/dev/null 2>&1 ||
      fail "$name: stdout missing '$expect_out' (got [$out]) err=[$err]"
  fi
  printf 'OK %s rc=%s out=%s\n' "$name" "$rc" "$out"
}

# Down once then Enter -> beta
run_keys down_enter "[b'\\x1b[B', b'\\r']" 0 "2|beta|Beta station"

# Two downs then Enter -> gamma
run_keys down2_enter "[b'\\x1b[B', b'\\x1b[B', b'\\r']" 0 "3|gamma|Gamma station"

# Application cursor keys SS3: ESC O B
run_keys ss3_down_enter "[b'\\x1bOB', b'\\r']" 0 "2|beta|Beta station"

# j then Enter
run_keys j_enter "[b'j', b'\\r']" 0 "2|beta|Beta station"

# Up from first wraps to last then Enter -> done
run_keys up_wrap_enter "[b'\\x1b[A', b'\\r']" 0 "4|done|完成并退出"

# b = back
run_keys back_b "[b'b']" 1 ""

# q = quit
run_keys quit_q "[b'q']" 2 ""

# Incomplete ESC alone must NOT back out (timeout ignore, then Enter keeps default)
run_keys bare_esc_then_enter "[b'\\x1b', b'\\r']" 0 "1|alpha|Alpha station"

# Modified arrow ESC [ 1 ; 2 B (shift-down)
run_keys modified_down "[b'\\x1b[1;2B', b'\\r']" 0 "2|beta|Beta station"

printf 'OK: codex-config-select PTY smoke passed\n'
