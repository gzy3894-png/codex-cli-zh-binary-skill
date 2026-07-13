#!/usr/bin/env python3
# Masked secret line reader for Codex for TUI config mode.
# Protocol:
#   args: --prompt TEXT [--tty PATH] [--allow-empty]
#   success stdout: the secret value (no trailing newline)
#   exit 0=ok 3=error
#
# Interactive TTY: no-echo, show • per char, Enter confirms, Backspace edits.
# Bare Esc is ignored (never cancels) so delayed arrow sequences cannot abort.
# FORCE_STDIN / non-TTY: plain line read from stdin (for UI smoke tests).

from __future__ import annotations

import argparse
import os
import select
import sys
import termios
import tty
from typing import Optional


def read_byte(fd: int, timeout: float = 0.0) -> Optional[bytes]:
    ready, _, _ = select.select([fd], [], [], timeout)
    if not ready:
        return None
    data = os.read(fd, 1)
    if not data:
        return None
    return data


def drain_escape(fd: int) -> Optional[bytes]:
    """Consume CSI/SS3 arrow (or bare ESC). Never treat as cancel.

    Returns a pushback byte when the byte after ESC is not a sequence start,
    so accidental ESC does not swallow the next typed character.
    """
    nxt = read_byte(fd, 0.35)
    if nxt is None:
        return None
    if nxt == b"[":
        for _ in range(16):
            ch = read_byte(fd, 0.2)
            if ch is None:
                return None
            if b"@" <= ch <= b"~":
                return None
        return None
    if nxt == b"O":
        read_byte(fd, 0.2)
        return None
    return nxt


def redraw(out, prompt: str, n: int) -> None:
    out.write("\r\033[K")
    out.write(prompt)
    if n > 0:
        out.write("•" * n)
    out.flush()


def decode_char(fd: int, first: bytes) -> str:
    """Decode one UTF-8 character starting with first byte."""
    if not first:
        return ""
    b0 = first[0]
    if b0 < 0x80:
        return first.decode("latin1")
    if 0xC2 <= b0 <= 0xDF:
        need = 2
    elif 0xE0 <= b0 <= 0xEF:
        need = 3
    elif 0xF0 <= b0 <= 0xF4:
        need = 4
    else:
        return ""
    raw = bytearray(first)
    while len(raw) < need:
        more = read_byte(fd, 0.05)
        if more is None:
            break
        raw.extend(more)
    try:
        return bytes(raw).decode("utf-8")
    except UnicodeDecodeError:
        return ""


def read_secret_interactive(prompt: str, tty_path: str) -> str:
    tty_in = open(tty_path, "rb", buffering=0)
    tty_out = open(tty_path, "w", encoding="utf-8", errors="replace")
    fd = tty_in.fileno()
    old = termios.tcgetattr(fd)
    buf: list[str] = []
    pending: Optional[bytes] = None
    try:
        tty.setcbreak(fd)
        tty_out.write("（密文输入，显示 •；回车确认）\n")
        tty_out.flush()
        redraw(tty_out, prompt, 0)
        while True:
            if pending is not None:
                data = pending
                pending = None
            else:
                data = read_byte(fd, 120.0)
            if data is None:
                continue
            if data in (b"\r", b"\n"):
                tty_out.write("\n")
                tty_out.flush()
                return "".join(buf)
            if data == b"\x1b":
                pushback = drain_escape(fd)
                if pushback is not None:
                    pending = pushback
                continue
            if data in (b"\x7f", b"\b"):
                if buf:
                    buf.pop()
                    redraw(tty_out, prompt, len(buf))
                continue
            if data == b"\x03":
                tty_out.write("\n")
                tty_out.flush()
                raise KeyboardInterrupt
            if data == b"\x04":
                if not buf:
                    tty_out.write("\n")
                    tty_out.flush()
                    return ""
                continue
            if data == b"\x15":
                buf.clear()
                redraw(tty_out, prompt, 0)
                continue
            if data[0] < 0x20:
                continue
            ch = decode_char(fd, data)
            if not ch:
                continue
            buf.append(ch)
            redraw(tty_out, prompt, len(buf))
    finally:
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except termios.error:
            pass
        tty_in.close()
        tty_out.close()


def read_secret_plain() -> str:
    line = sys.stdin.readline()
    if line.endswith("\n"):
        line = line[:-1]
    if line.endswith("\r"):
        line = line[:-1]
    return line


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Codex config masked secret reader")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--tty", default="/dev/tty")
    parser.add_argument("--allow-empty", action="store_true")
    args = parser.parse_args(argv)

    prompt = args.prompt
    if not prompt.endswith((" ", "：", ":")):
        if not prompt.endswith(":"):
            prompt = prompt + ":"
        prompt = prompt + " "
    elif prompt.endswith(":") and not prompt.endswith(": "):
        prompt = prompt + " "

    force_stdin = os.environ.get("CODEX_ZH_FORCE_STDIN", "0") == "1"
    tty_path = args.tty
    use_tty = (not force_stdin) and os.access(tty_path, os.R_OK | os.W_OK)

    try:
        if use_tty:
            value = read_secret_interactive(prompt, tty_path)
        else:
            sys.stderr.write(prompt)
            sys.stderr.flush()
            value = read_secret_plain()
    except KeyboardInterrupt:
        sys.stderr.write("\n")
        return 3
    except OSError as exc:
        sys.stderr.write(f"secret-read: {exc}\n")
        return 3

    # allow-empty is informational for callers; always emit value on stdout.
    _ = args.allow_empty
    sys.stdout.write(value)
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
