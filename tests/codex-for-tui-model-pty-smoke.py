#!/usr/bin/env python3
"""Exercise the real Codex TUI model picker through a PTY.

This test intentionally types slash commands at human speed. Codex has paste-burst
protection, so writing ``/model\r`` in one PTY write can turn Enter into a pasted
newline instead of submitting the command.
"""

from __future__ import annotations

import argparse
import codecs
import fcntl
import json
import os
import pty
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unicodedata
from pathlib import Path


ROWS = 50
COLS = 140


class TerminalScreen:
    """Small VT100/xterm screen emulator for deterministic TUI assertions."""

    def __init__(self, rows: int, cols: int) -> None:
        self.rows = rows
        self.cols = cols
        self.cells = [[" "] * cols for _ in range(rows)]
        self.row = 0
        self.col = 0
        self.saved_row = 0
        self.saved_col = 0
        self.state = "normal"
        self.sequence = ""
        self.osc_esc = False

    def text(self) -> str:
        return "\n".join("".join(line).rstrip() for line in self.cells).rstrip()

    def feed(self, text: str) -> None:
        for char in text:
            if self.state == "osc":
                if char == "\a":
                    self.state = "normal"
                    self.osc_esc = False
                elif self.osc_esc and char == "\\":
                    self.state = "normal"
                    self.osc_esc = False
                else:
                    self.osc_esc = char == "\x1b"
                continue

            if self.state == "charset":
                self.state = "normal"
                continue

            if self.state == "esc":
                self._feed_escape(char)
                continue

            if self.state == "csi":
                if "@" <= char <= "~":
                    self._handle_csi(self.sequence, char)
                    self.sequence = ""
                    self.state = "normal"
                else:
                    self.sequence += char
                continue

            if char == "\x1b":
                self.state = "esc"
            elif char == "\r":
                self.col = 0
            elif char in ("\n", "\v", "\f"):
                self._line_feed()
            elif char == "\b":
                self.col = max(0, self.col - 1)
            elif char == "\t":
                self.col = min(self.cols - 1, ((self.col // 8) + 1) * 8)
            elif ord(char) >= 0x20 and char != "\x7f":
                self._put(char)

    def _feed_escape(self, char: str) -> None:
        self.state = "normal"
        if char == "[":
            self.sequence = ""
            self.state = "csi"
        elif char == "]":
            self.state = "osc"
            self.osc_esc = False
        elif char in ("(", ")", "*", "+"):
            self.state = "charset"
        elif char == "7":
            self.saved_row, self.saved_col = self.row, self.col
        elif char == "8":
            self.row, self.col = self.saved_row, self.saved_col
        elif char == "D":
            self._line_feed()
        elif char == "E":
            self._line_feed()
            self.col = 0
        elif char == "M":
            if self.row > 0:
                self.row -= 1
            else:
                self.cells.insert(0, [" "] * self.cols)
                self.cells.pop()
        elif char == "c":
            self.cells = [[" "] * self.cols for _ in range(self.rows)]
            self.row = 0
            self.col = 0

    @staticmethod
    def _params(sequence: str) -> list[int]:
        sequence = sequence.lstrip("?<=>")
        if not sequence:
            return [0]
        values: list[int] = []
        for part in sequence.split(";"):
            try:
                values.append(int(part) if part else 0)
            except ValueError:
                values.append(0)
        return values

    def _handle_csi(self, sequence: str, final: str) -> None:
        params = self._params(sequence)
        first = params[0] if params else 0
        amount = first or 1

        if final in ("H", "f"):
            row = (params[0] if params else 1) or 1
            col = (params[1] if len(params) > 1 else 1) or 1
            self.row = min(self.rows - 1, row - 1)
            self.col = min(self.cols - 1, col - 1)
        elif final == "A":
            self.row = max(0, self.row - amount)
        elif final in ("B", "e"):
            self.row = min(self.rows - 1, self.row + amount)
        elif final == "C":
            self.col = min(self.cols - 1, self.col + amount)
        elif final == "D":
            self.col = max(0, self.col - amount)
        elif final == "E":
            self.row = min(self.rows - 1, self.row + amount)
            self.col = 0
        elif final == "F":
            self.row = max(0, self.row - amount)
            self.col = 0
        elif final in ("G", "`"):
            self.col = min(self.cols - 1, amount - 1)
        elif final == "d":
            self.row = min(self.rows - 1, amount - 1)
        elif final == "J":
            self._erase_display(first)
        elif final == "K":
            self._erase_line(first)
        elif final == "s":
            self.saved_row, self.saved_col = self.row, self.col
        elif final == "u":
            self.row, self.col = self.saved_row, self.saved_col
        elif final == "@":
            count = min(amount, self.cols - self.col)
            line = self.cells[self.row]
            line[self.col : self.col] = [" "] * count
            del line[self.cols :]
        elif final == "P":
            count = min(amount, self.cols - self.col)
            line = self.cells[self.row]
            del line[self.col : self.col + count]
            line.extend([" "] * count)
        elif final == "X":
            end = min(self.cols, self.col + amount)
            self.cells[self.row][self.col : end] = [" "] * (end - self.col)
        elif final == "L":
            for _ in range(min(amount, self.rows - self.row)):
                self.cells.insert(self.row, [" "] * self.cols)
                self.cells.pop()
        elif final == "M":
            for _ in range(min(amount, self.rows - self.row)):
                self.cells.pop(self.row)
                self.cells.append([" "] * self.cols)
        elif final == "S":
            for _ in range(min(amount, self.rows)):
                self.cells.pop(0)
                self.cells.append([" "] * self.cols)
        elif final == "T":
            for _ in range(min(amount, self.rows)):
                self.cells.insert(0, [" "] * self.cols)
                self.cells.pop()

    def _erase_display(self, mode: int) -> None:
        if mode in (2, 3):
            self.cells = [[" "] * self.cols for _ in range(self.rows)]
        elif mode == 0:
            self.cells[self.row][self.col :] = [" "] * (self.cols - self.col)
            for row in range(self.row + 1, self.rows):
                self.cells[row] = [" "] * self.cols
        elif mode == 1:
            for row in range(0, self.row):
                self.cells[row] = [" "] * self.cols
            self.cells[self.row][: self.col + 1] = [" "] * (self.col + 1)

    def _erase_line(self, mode: int) -> None:
        if mode == 0:
            self.cells[self.row][self.col :] = [" "] * (self.cols - self.col)
        elif mode == 1:
            self.cells[self.row][: self.col + 1] = [" "] * (self.col + 1)
        elif mode == 2:
            self.cells[self.row] = [" "] * self.cols

    def _line_feed(self) -> None:
        if self.row == self.rows - 1:
            self.cells.pop(0)
            self.cells.append([" "] * self.cols)
        else:
            self.row += 1

    def _put(self, char: str) -> None:
        if unicodedata.combining(char):
            target = max(0, self.col - 1)
            self.cells[self.row][target] += char
            return

        width = 2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
        if self.col >= self.cols:
            self.col = 0
            self._line_feed()
        self.cells[self.row][self.col] = char
        if width == 2 and self.col + 1 < self.cols:
            self.cells[self.row][self.col + 1] = ""
        self.col += width


class PtyCodex:
    def __init__(
        self,
        command: list[str],
        cwd: Path,
        env: dict[str, str],
        timeout_scale: float,
    ) -> None:
        self.command = command
        self.cwd = cwd
        self.env = env
        self.timeout_scale = timeout_scale
        self.master = -1
        self.process: subprocess.Popen[bytes] | None = None
        self.raw = bytearray()
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.screen = TerminalScreen(ROWS, COLS)

    def start(self) -> None:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        self.master = master
        self.process = subprocess.Popen(
            self.command,
            cwd=self.cwd,
            env=self.env,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            start_new_session=True,
        )
        os.close(slave)
        flags = fcntl.fcntl(master, fcntl.F_GETFL)
        fcntl.fcntl(master, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    def close(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.process.wait(timeout=3)
        if self.master >= 0:
            try:
                os.close(self.master)
            except OSError:
                pass
            self.master = -1

    def drain(self, seconds: float = 0.1) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.process is not None and self.process.poll() is not None:
                return
            ready, _, _ = select.select([self.master], [], [], 0.05)
            if not ready:
                continue
            try:
                data = os.read(self.master, 65536)
            except BlockingIOError:
                continue
            except OSError:
                return
            if not data:
                return
            self.raw.extend(data)
            self.screen.feed(self.decoder.decode(data))

    def wait_for(self, needle: str, timeout: float) -> str:
        deadline = time.monotonic() + timeout * self.timeout_scale
        last = ""
        while time.monotonic() < deadline:
            self.drain(0.15)
            last = self.screen.text()
            if needle in last:
                return last
            if self.process is not None and self.process.poll() is not None:
                raise AssertionError(
                    f"Codex exited with {self.process.returncode} while waiting for {needle!r}"
                )
        raise AssertionError(
            f"timed out waiting for {needle!r}; final screen follows:\n{last}"
        )

    def type_human(self, text: str) -> None:
        for byte in text.encode("utf-8"):
            os.write(self.master, bytes([byte]))
            time.sleep(0.08 * self.timeout_scale)
            self.drain(0.02)

    def key(self, data: bytes, settle: float = 0.2) -> None:
        os.write(self.master, data)
        self.drain(settle * self.timeout_scale)


def fail(message: str, screen: str, raw_path: Path, screen_path: Path) -> None:
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    screen_path.write_text(screen, encoding="utf-8")
    raise AssertionError(f"{message}\nfinal screen:\n{screen}")


def write_runtime(root: Path, catalog_source: Path) -> tuple[Path, Path]:
    home = root / "home"
    runtime = root / "runtime"
    work = root / "work"
    sqlite = runtime / "sqlite-builds" / "pty-apk-2.4.8"
    runtime.mkdir(parents=True)
    work.mkdir()
    sqlite.mkdir(parents=True)
    shutil.copyfile(catalog_source, runtime / "model_catalog.json")

    auth_command = root / "print-openai-api-key.sh"
    auth_command.write_text(
        "#!/usr/bin/env sh\nprintf '%s\\n' 'codex-for-tui-pty-smoke'\n",
        encoding="utf-8",
    )
    auth_command.chmod(0o755)

    provider_id = "codex_tui_pty_smoke"
    config = f"""\
model_provider = "{provider_id}"
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
model_catalog_json = "{runtime / "model_catalog.json"}"
sqlite_home = "{sqlite}"

[model_providers.{provider_id}]
name = "PTY Smoke"
base_url = "http://127.0.0.1:9/v1"
wire_api = "responses"
requires_openai_auth = false

[model_providers.{provider_id}.auth]
command = "{auth_command}"
args = []
timeout_ms = 5000
refresh_interval_ms = 300000
cwd = "{root}"

[projects."{work}"]
trust_level = "trusted"

[tui.model_availability_nux]
"gpt-5.6-sol" = 1
"""
    (runtime / "config.toml").write_text(config, encoding="utf-8")
    (runtime / "auth.json").write_text("{}\n", encoding="utf-8")
    return home, runtime


def catalog_assertions(catalog_source: Path) -> None:
    payload = json.loads(catalog_source.read_text(encoding="utf-8"))
    models = payload["models"]
    by_slug = {model["slug"]: model for model in models}
    sol = by_slug["gpt-5.6-sol"]
    efforts = [entry["effort"] for entry in sol["supported_reasoning_levels"]]
    assert sol["context_window"] == 372000
    assert sol["default_reasoning_level"] == "low"
    assert efforts == ["low", "medium", "high", "xhigh", "max", "ultra"]
    assert all(
        model.get("visibility") == "hide"
        for model in models
        if model["slug"].startswith("codex-auto-")
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument(
        "--qemu",
        type=Path,
        help="Run the aarch64 binary through this qemu-aarch64 executable.",
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "android-arm64-musl"
        / "data"
        / "openai-models.json",
    )
    parser.add_argument("--keep", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    binary = args.binary.resolve()
    catalog = args.catalog.resolve()
    if not binary.is_file():
        raise SystemExit(f"missing Codex binary: {binary}")
    if not catalog.is_file():
        raise SystemExit(f"missing model catalog: {catalog}")
    catalog_assertions(catalog)

    root = Path(tempfile.mkdtemp(prefix="codex-for-tui-model-pty.")).resolve()
    raw_path = root / "tui.raw"
    screen_path = root / "screen.txt"
    home, runtime = write_runtime(root, catalog)
    command = [str(binary), "--no-alt-screen"]
    timeout_scale = 1.0
    if args.qemu:
        command = [str(args.qemu.resolve()), str(binary), "--no-alt-screen"]
        timeout_scale = 3.0

    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "CODEX_HOME": str(runtime),
            "CODEX_SQLITE_HOME": str(runtime / "sqlite-builds" / "pty-apk-2.4.8"),
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "NO_COLOR": "1",
            "CODEX_CI": "1",
        }
    )

    session = PtyCodex(command, root / "work", env, timeout_scale)
    keep = args.keep
    try:
        session.start()
        session.wait_for("gpt-5.6-sol xhigh", 15)

        session.type_human("/model")
        # Paste-burst protection must expire before Enter submits the command.
        session.drain(0.8 * timeout_scale)
        session.key(b"\r", settle=0.5)
        model_screen = session.wait_for("选择模型和推理等级", 10)

        required_models = [
            "gpt-5.6-sol",
            "gpt-5.6-terra",
            "gpt-5.6-luna",
            "gpt-5.5",
            "gpt-5.4",
        ]
        for model in required_models:
            if model not in model_screen:
                fail(
                    f"/model did not show expected visible model {model}",
                    model_screen,
                    raw_path,
                    screen_path,
                )
        for forbidden in ("全部模型", "codex-auto-"):
            if forbidden in model_screen:
                fail(
                    f"/model opened an intermediate/auto page containing {forbidden!r}",
                    model_screen,
                    raw_path,
                    screen_path,
                )

        session.key(b"\r", settle=0.5)
        reasoning_screen = session.wait_for("为 gpt-5.6-sol 选择推理等级", 10)
        for label in ("低（默认）", "中", "高", "极高", "Max", "Ultra"):
            if label not in reasoning_screen:
                fail(
                    f"reasoning picker is missing upstream level {label!r}",
                    reasoning_screen,
                    raw_path,
                    screen_path,
                )
        if "codex-auto-" in reasoning_screen:
            fail(
                "reasoning picker leaked an auto helper model",
                reasoning_screen,
                raw_path,
                screen_path,
            )

        raw_path.write_bytes(session.raw)
        screen_path.write_text(reasoning_screen, encoding="utf-8")
        print("codex-for-tui model PTY smoke: PASS")
        print(f"binary={binary}")
        print("model_picker=direct-all-visible-models")
        print("gpt-5.6-sol=low,medium,high,xhigh,max,ultra")
        print("codex-auto=hidden")
        if keep:
            print(f"artifacts={root}")
        return 0
    except Exception:
        keep = True
        raw_path.write_bytes(session.raw)
        screen_path.write_text(session.screen.text(), encoding="utf-8")
        print(f"PTY failure artifacts: {root}", file=sys.stderr)
        raise
    finally:
        session.close()
        if not keep:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
