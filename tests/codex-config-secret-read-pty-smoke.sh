#!/usr/bin/env sh
# Local PTY smoke for codex-config-secret-read.py — must pass before APK release.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SECRET_PY="$ROOT_DIR/android-arm64-musl/libexec/codex-config-secret-read.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-secret-pty.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SECRET_PY" ] || fail "missing $SECRET_PY"
chmod +x "$SECRET_PY" || true

run_keys() {
  name="$1"
  keys_py="$2"
  expect_rc="$3"
  expect_out="$4"
  python3 - "$SECRET_PY" "$TMP/out.$name" "$keys_py" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

secret_py, out_path, keys_spec = sys.argv[1:4]
keys = eval(keys_spec, {"__builtins__": {}})

master, slave = pty.openpty()
env = os.environ.copy()
env["TERM"] = "xterm-256color"
env.pop("CODEX_ZH_FORCE_STDIN", None)
proc = subprocess.Popen(
    [
        sys.executable,
        secret_py,
        "--prompt",
        "API Key（回车确认；b 返回，q 退出）",
        "--tty",
        os.ttyname(slave),
    ],
    stdin=slave,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
    close_fds=True,
)
os.close(slave)
time.sleep(0.15)

for chunk in keys:
    if isinstance(chunk, str):
        chunk = chunk.encode("latin1")
    os.write(master, chunk)
    time.sleep(0.04)

deadline = time.time() + 3.0
tty_dump = b""
while time.time() < deadline:
    r, _, _ = select.select([master], [], [], 0.05)
    if r:
        try:
            chunk = os.read(master, 4096)
            if not chunk:
                break
            tty_dump += chunk
        except OSError:
            break
    if proc.poll() is not None:
        # Drain any remaining after process exit.
        for _ in range(20):
            r, _, _ = select.select([master], [], [], 0.02)
            if not r:
                break
            try:
                chunk = os.read(master, 4096)
                if not chunk:
                    break
                tty_dump += chunk
            except OSError:
                break
        break
rc = proc.wait(timeout=2)
stdout = proc.stdout.read() if proc.stdout else b""
stderr = proc.stderr.read() if proc.stderr else b""
os.close(master)
open(out_path + ".rc", "w", encoding="utf-8").write(str(rc))
open(out_path + ".out", "wb").write(stdout)
open(out_path + ".err", "wb").write(stderr)
open(out_path + ".tty", "wb").write(tty_dump)
print(rc, stdout.decode("utf-8", "replace"))
PY
  rc="$(cat "$TMP/out.$name.rc")"
  out="$(cat "$TMP/out.$name.out")"
  err="$(cat "$TMP/out.$name.err" 2>/dev/null || true)"
  tty="$(cat "$TMP/out.$name.tty" 2>/dev/null || true)"
  [ "$rc" = "$expect_rc" ] || fail "$name: rc=$rc expected $expect_rc out=[$out] err=[$err]"
  if [ -n "$expect_out" ]; then
    [ "$out" = "$expect_out" ] || fail "$name: stdout=[$out] expected [$expect_out] err=[$err]"
  fi
  # Bullets should appear on the TTY for non-empty typed secrets.
  case "$name" in
    type_secret|backspace_edit)
      printf '%s' "$tty" | grep -F '•' >/dev/null 2>&1 ||
        fail "$name: tty dump missing bullet feedback"
      printf '%s' "$tty" | grep -F '密文输入' >/dev/null 2>&1 ||
        fail "$name: tty dump missing 密文输入 note"
      ;;
  esac
  # Multi-char secret value must not appear in TTY dump (only bullets).
  # Skip single-char / control tokens (b/q) — too easy to false-positive on noise.
  case "$expect_out" in
    ""|b|q|x) ;;
    *)
      printf '%s' "$tty" | grep -F -- "$expect_out" >/dev/null 2>&1 &&
        fail "$name: secret leaked to TTY dump"
      ;;
  esac
  printf 'OK %s rc=%s out=%s\n' "$name" "$rc" "$out"
}

# Type sk-test then Enter
run_keys type_secret "[b's', b'k', b'-', b't', b'e', b's', b't', b'\\r']" 0 "sk-test"

# Backspace edits: type abX, backspace, c, enter -> abc
run_keys backspace_edit "[b'a', b'b', b'X', b'\\x7f', b'c', b'\\r']" 0 "abc"

# Empty Enter (caller decides empty invalid)
run_keys empty_enter "[b'\\r']" 0 ""

# Whole-line b for back (caller interprets)
run_keys line_b "[b'b', b'\\r']" 0 "b"

# Bare ESC must not abort; then type x + Enter
run_keys bare_esc_then_x "[b'\\x1b', b'x', b'\\r']" 0 "x"

# FORCE_STDIN plain path
FORCE_OUT="$(printf 'piped-secret\n' | CODEX_ZH_FORCE_STDIN=1 python3 "$SECRET_PY" --prompt "API Key" --tty /dev/null)"
[ "$FORCE_OUT" = "piped-secret" ] || fail "FORCE_STDIN path got [$FORCE_OUT]"
printf 'OK force_stdin\n'

printf 'codex-config-secret-read PTY smoke passed\n'
