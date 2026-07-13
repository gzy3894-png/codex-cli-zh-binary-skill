#!/usr/bin/env python3
# Interactive list picker for Codex for TUI config mode.
# stdin/stdout protocol for the shell wrapper:
#   args: --title TEXT --file PATH [--default N|ID] [--tty PATH]
#   success stdout: INDEX|ID|LABEL
#   exit 0=ok 1=back/cancel 2=quit 3=error
#
# Keys: Up/Down (CSI or SS3), j/k, Enter, b=back, q=quit.
# Bare Esc alone is ignored (never treated as back) so delayed arrow
# sequences cannot eject the user from config mode.

from __future__ import annotations

import argparse
import os
import select
import sys
import termios
import tty
from typing import List, Optional, Tuple


def load_items(path: str) -> List[Tuple[str, str]]:
    items: List[Tuple[str, str]] = []
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line:
                continue
            if "|" in line:
                item_id, label = line.split("|", 1)
            else:
                item_id, label = line, line
            items.append((item_id, label))
    return items


def resolve_default(items: List[Tuple[str, str]], default: str) -> int:
    if not default:
        return 0
    if default.isdigit():
        value = int(default)
        if 1 <= value <= len(items):
            return value - 1
    for idx, (item_id, _label) in enumerate(items):
        if item_id == default:
            return idx
    return 0


def read_key(fd: int, timeout: float = 0.0) -> Optional[str]:
    ready, _, _ = select.select([fd], [], [], timeout)
    if not ready:
        return None
    return os.read(fd, 1).decode("latin1", errors="ignore")


def read_after_escape(fd: int) -> Tuple[Optional[str], Optional[str]]:
    """After ESC was read, parse cursor sequence or return a pushback key.

    Returns (action, pushback_char):
      action in {up,down,left,right} when a full arrow sequence is read
      pushback_char set when the byte after ESC is not CSI/SS3 start
      both None when bare/incomplete ESC should be ignored
    Never treats ESC as "back".
    """
    nxt = read_key(fd, 0.35)
    if nxt is None:
        return None, None
    if nxt == "[":
        body = ""
        for _ in range(16):
            ch = read_key(fd, 0.2)
            if ch is None:
                return None, None
            body += ch
            if "@" <= ch <= "~":
                final = body[-1]
                if final in "ABCD":
                    return {"A": "up", "B": "down", "C": "right", "D": "left"}[final], None
                return None, None
        return None, None
    if nxt == "O":
        ch = read_key(fd, 0.2)
        if ch is None:
            return None, None
        if ch in "ABCD":
            return {"A": "up", "B": "down", "C": "right", "D": "left"}[ch], None
        return None, None
    return None, nxt


def display_width(text: str) -> int:
    width = 0
    for ch in text:
        o = ord(ch)
        if o == 0xFE0F:
            continue
        if (
            0x1100 <= o <= 0x115F
            or 0x2329 <= o <= 0x232A
            or 0x2E80 <= o <= 0xA4CF
            or 0xAC00 <= o <= 0xD7A3
            or 0xF900 <= o <= 0xFAFF
            or 0xFE10 <= o <= 0xFE6F
            or 0xFF00 <= o <= 0xFF60
            or 0xFFE0 <= o <= 0xFFE6
            or 0x1F300 <= o <= 0x1FAFF
        ):
            width += 2
        else:
            width += 1
    return width


def truncate(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if display_width(text) <= width:
        return text
    out = []
    used = 0
    for ch in text:
        w = display_width(ch)
        if used + w + 1 > width:
            break
        out.append(ch)
        used += w
    return "".join(out) + "…"


def pad_line(text: str, width: int) -> str:
    text = truncate(text, width)
    pad = max(0, width - display_width(text))
    return text + (" " * pad)


def render(
    out,
    title: str,
    items: List[Tuple[str, str]],
    index: int,
    height_hint: int,
    cols: int,
) -> None:
    out.write("\033[H\033[J")
    frame = max(28, min(cols, 56))
    max_visible = max(4, min(len(items), max(6, height_hint - 7)))
    if len(items) <= max_visible:
        start = 0
        end = len(items)
    else:
        start = max(0, min(index - max_visible // 2, len(items) - max_visible))
        end = start + max_visible

    lines: List[str] = []
    lines.append(pad_line(title or "配置", frame))
    lines.append(pad_line("", frame))
    if start > 0:
        lines.append(pad_line("  · · ·", frame))
    for i in range(start, end):
        _item_id, label = items[i]
        if i == index:
            # Explicit white bg + black fg (not reverse-video): reverse often
            # renders as a solid black bar on light Android terminal themes.
            body = truncate("  › " + label, frame)
            pad = max(0, frame - display_width(body))
            lines.append("\033[47;30m" + body + (" " * pad) + "\033[0m")
        else:
            lines.append(pad_line("    " + label, frame))
    if end < len(items):
        lines.append(pad_line("  · · ·", frame))
    lines.append(pad_line("", frame))
    lines.append(pad_line("↑↓ 移动  回车确认  b返回  q退出", frame))
    out.write("\n".join(lines) + "\n")
    out.flush()


def run_interactive(
    title: str,
    items: List[Tuple[str, str]],
    default_index: int,
    tty_path: str,
) -> int:
    index = max(0, min(len(items) - 1, default_index))
    tty_in = open(tty_path, "rb", buffering=0)
    tty_out = open(tty_path, "w", encoding="utf-8", errors="replace")
    fd = tty_in.fileno()
    old = termios.tcgetattr(fd)
    height_hint = 24
    cols = 40
    try:
        try:
            size = os.get_terminal_size(tty_out.fileno())
            height_hint = max(12, size.lines)
            cols = max(28, size.columns)
        except (OSError, AttributeError, ValueError):
            pass
        tty.setcbreak(fd)
        try:
            tty_out.write("\033[?25l")
            tty_out.flush()
        except OSError:
            pass
        pending: Optional[str] = None
        while True:
            render(tty_out, title, items, index, height_hint, cols)
            if pending is not None:
                ch = pending
                pending = None
            else:
                ch = read_key(fd, 60.0)
            if ch is None:
                continue
            if ch == "\x1b":
                action, pushback = read_after_escape(fd)
                if action == "up":
                    index = (index - 1) % len(items)
                    continue
                if action == "down":
                    index = (index + 1) % len(items)
                    continue
                if pushback is not None:
                    pending = pushback
                continue
            if ch in ("\r", "\n"):
                item_id, label = items[index]
                sys.stdout.write(f"{index + 1}|{item_id}|{label}\n")
                sys.stdout.flush()
                return 0
            if ch in ("b", "B"):
                return 1
            if ch in ("q", "Q"):
                return 2
            if ch in ("k", "K", "p", "P"):
                index = (index - 1) % len(items)
                continue
            if ch in ("j", "J", "n", "N"):
                index = (index + 1) % len(items)
                continue
            if ch.isdigit() and ch != "0":
                jump = int(ch)
                if 1 <= jump <= len(items):
                    index = jump - 1
                continue
    finally:
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except termios.error:
            pass
        try:
            tty_out.write("\033[?25h\n")
            tty_out.flush()
        except OSError:
            pass
        tty_in.close()
        tty_out.close()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Codex config list picker")
    parser.add_argument("--title", default="")
    parser.add_argument("--file", required=True)
    parser.add_argument("--default", default="1")
    parser.add_argument("--tty", default="/dev/tty")
    args = parser.parse_args(argv)

    try:
        items = load_items(args.file)
    except OSError as exc:
        sys.stderr.write(f"select: cannot read items: {exc}\n")
        return 3
    if not items:
        sys.stderr.write("select: empty item list\n")
        return 3

    default_index = resolve_default(items, args.default)
    tty_path = args.tty
    if not (os.access(tty_path, os.R_OK | os.W_OK)):
        sys.stderr.write(f"select: tty not usable: {tty_path}\n")
        return 3

    try:
        return run_interactive(args.title, items, default_index, tty_path)
    except Exception as exc:  # noqa: BLE001 - surface to shell fallback
        sys.stderr.write(f"select: interactive failed: {exc}\n")
        return 3


if __name__ == "__main__":
    sys.exit(main())
