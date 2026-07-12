#!/usr/bin/env python3
"""Stage per-session Codex model choices as the next profile defaults.

The adapter is intentionally separate from the profile engine. It receives one
launch context through environment variables, reads only structured
``thread_settings_applied`` records, and writes a small generation-bound
pending document. It never stores prompts or transcript paths.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator


SCHEMA_VERSION = 1
PROFILE_ID_RE = re.compile(r"^p-[0-9a-f]{12}$")
GENERATION_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    r"[0-9a-f]{4}-[0-9a-f]{12}"
)
SAFE_VALUE_RE = re.compile(r"^[A-Za-z0-9._:-]+$")
MAX_HOOK_INPUT_BYTES = 1024 * 1024
MAX_REVERSE_SCAN_BYTES = 16 * 1024 * 1024
MAX_JSON_LINE_BYTES = 1024 * 1024
MAX_MIGRATION_FILES = 32
READ_CHUNK_BYTES = 64 * 1024


class DefaultsError(Exception):
    pass


@dataclass(frozen=True)
class LaunchContext:
    control_home: Path
    profile_id: str
    generation: str
    baseline_model: str
    baseline_effort: str | None
    provider_id: str


def utc_now() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def emit(**payload: Any) -> None:
    print(json.dumps({"ok": True, **payload}, ensure_ascii=False, sort_keys=True))


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)


def atomic_write_json(path: Path, value: Any) -> None:
    ensure_private_dir(path.parent)
    data = (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        tmp.chmod(0o600)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def checked_env(name: str, *, allow_empty: bool = False) -> str:
    value = os.environ.get(name, "").strip()
    if not value and not allow_empty:
        raise DefaultsError(f"missing environment: {name}")
    if len(value) > 256 or "\x00" in value or "\n" in value or "\r" in value:
        raise DefaultsError(f"invalid environment: {name}")
    return value


def launch_context() -> LaunchContext:
    control_value = checked_env("CODEX_FOR_TUI_CONTROL_HOME")
    control_home = Path(control_value).expanduser().resolve()
    profile_id = checked_env("CODEX_FOR_TUI_PROFILE_ID")
    generation = checked_env("CODEX_FOR_TUI_PROFILE_GENERATION")
    model = checked_env("CODEX_FOR_TUI_BASELINE_MODEL", allow_empty=True)
    effort = checked_env(
        "CODEX_FOR_TUI_BASELINE_REASONING_EFFORT",
        allow_empty=True,
    )
    provider = checked_env("CODEX_FOR_TUI_MODEL_PROVIDER_ID", allow_empty=True)
    if not PROFILE_ID_RE.fullmatch(profile_id):
        raise DefaultsError("invalid profile id")
    if not GENERATION_RE.fullmatch(generation):
        raise DefaultsError("invalid profile generation")
    for label, value in (("model", model), ("effort", effort), ("provider", provider)):
        if value and not SAFE_VALUE_RE.fullmatch(value):
            raise DefaultsError(f"invalid {label}")
    return LaunchContext(
        control_home=control_home,
        profile_id=profile_id,
        generation=generation,
        baseline_model=model,
        baseline_effort=effort or None,
        provider_id=provider,
    )


def profile_generation(context: LaunchContext) -> str:
    managed = (
        context.control_home
        / "config-profiles-v2"
        / "profiles"
        / context.profile_id
        / "managed.toml"
    )
    try:
        return hashlib.sha256(managed.read_bytes()).hexdigest()
    except OSError as exc:
        raise DefaultsError("active profile managed data is unavailable") from exc


def reverse_lines(path: Path) -> Iterator[bytes]:
    """Yield bounded complete lines from the tail without retaining huge images."""
    size = path.stat().st_size
    position = size
    remaining = min(size, MAX_REVERSE_SCAN_BYTES)
    suffix = b""
    dropping_oversized = False
    with path.open("rb") as handle:
        while position > 0 and remaining > 0:
            count = min(READ_CHUNK_BYTES, position, remaining)
            position -= count
            remaining -= count
            handle.seek(position)
            chunk = handle.read(count)
            parts = chunk.split(b"\n")
            if len(parts) == 1:
                if dropping_oversized:
                    continue
                suffix = parts[0] + suffix
                if len(suffix) > MAX_JSON_LINE_BYTES:
                    suffix = b""
                    dropping_oversized = True
                continue

            connected = parts[-1] + suffix
            if not dropping_oversized and len(connected) <= MAX_JSON_LINE_BYTES:
                yield connected
            dropping_oversized = False
            for line in reversed(parts[1:-1]):
                if len(line) <= MAX_JSON_LINE_BYTES:
                    yield line
            suffix = parts[0]
            if len(suffix) > MAX_JSON_LINE_BYTES:
                suffix = b""
                dropping_oversized = True
        if position == 0 and not dropping_oversized and suffix:
            yield suffix


def event_settings(line: bytes, path: Path) -> dict[str, Any] | None:
    try:
        root = json.loads(line)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    payload = root.get("payload") if isinstance(root, dict) else None
    if (
        root.get("type") != "event_msg"
        or not isinstance(payload, dict)
        or payload.get("type") != "thread_settings_applied"
    ):
        return None
    settings = payload.get("thread_settings")
    if not isinstance(settings, dict):
        return None
    collaboration = settings.get("collaboration_mode")
    if not isinstance(collaboration, dict) or collaboration.get("mode") != "default":
        return None
    model = settings.get("model")
    effort = settings.get("reasoning_effort")
    provider = settings.get("model_provider_id")
    if not isinstance(model, str) or not model or not SAFE_VALUE_RE.fullmatch(model):
        return None
    if effort is not None and (
        not isinstance(effort, str) or not SAFE_VALUE_RE.fullmatch(effort)
    ):
        return None
    if provider is not None and (
        not isinstance(provider, str) or not SAFE_VALUE_RE.fullmatch(provider)
    ):
        return None
    observed_at = root.get("timestamp")
    if not isinstance(observed_at, str) or len(observed_at) > 64:
        observed_at = dt.datetime.fromtimestamp(
            path.stat().st_mtime,
            tz=dt.timezone.utc,
        ).isoformat().replace("+00:00", "Z")
    match = UUID_RE.search(path.name)
    return {
        "model": model,
        "reasoning_effort": effort,
        "model_provider_id": provider or "",
        "observed_at": observed_at,
        "source_session_id": match.group(0).lower() if match else "",
    }


def latest_settings(path: Path, context: LaunchContext) -> dict[str, Any] | None:
    for line in reverse_lines(path):
        candidate = event_settings(line, path)
        if candidate is None:
            continue
        if context.provider_id and candidate["model_provider_id"] != context.provider_id:
            continue
        return candidate
    return None


def allowed_transcript(value: str, context: LaunchContext) -> Path:
    candidate = Path(value).expanduser()
    if not candidate.is_absolute() or candidate.suffix != ".jsonl":
        raise DefaultsError("invalid transcript path")
    resolved = candidate.resolve(strict=True)
    roots = [context.control_home / "sessions"]
    runtime_home = os.environ.get("CODEX_HOME", "").strip()
    if runtime_home:
        roots.append(Path(runtime_home).expanduser() / "sessions")
    for root in roots:
        try:
            resolved.relative_to(root.resolve(strict=False))
            return resolved
        except ValueError:
            continue
    raise DefaultsError("transcript path is outside session roots")


def observed_order(value: Any) -> float:
    if not isinstance(value, str):
        return 0.0
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


@contextlib.contextmanager
def state_lock(context: LaunchContext) -> Iterator[None]:
    state = context.control_home / "install-state" / "session-defaults"
    ensure_private_dir(state)
    lock = state / ".lock"
    with lock.open("a+", encoding="utf-8") as handle:
        os.fchmod(handle.fileno(), 0o600)
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        yield


def stage_settings(
    context: LaunchContext,
    settings: dict[str, Any],
    source: str,
) -> dict[str, Any]:
    state = context.control_home / "install-state" / "session-defaults"
    pending_path = state / f"{context.profile_id}.json"
    status_path = state / f"{context.profile_id}.status.json"
    with state_lock(context):
        if profile_generation(context) != context.generation:
            result = {"status": "ignored", "reason": "stale-generation"}
        else:
            existing = read_json(pending_path)
            changed = (
                settings["model"] != context.baseline_model
                or settings["reasoning_effort"] != context.baseline_effort
            )
            same_source = (
                isinstance(existing, dict)
                and existing.get("base_generation") == context.generation
                and existing.get("source_session_id")
                == settings.get("source_session_id")
            )
            if not changed:
                if same_source and observed_order(settings.get("observed_at")) >= observed_order(
                    existing.get("observed_at")
                ):
                    pending_path.unlink(missing_ok=True)
                    result = {"status": "cancelled", "reason": "returned-to-baseline"}
                else:
                    result = {"status": "unchanged", "reason": "matches-baseline"}
            elif (
                isinstance(existing, dict)
                and existing.get("base_generation") == context.generation
                and observed_order(existing.get("observed_at"))
                > observed_order(settings.get("observed_at"))
            ):
                result = {"status": "ignored", "reason": "older-observation"}
            else:
                pending = {
                    "schema_version": SCHEMA_VERSION,
                    "profile_id": context.profile_id,
                    "base_generation": context.generation,
                    "model": settings["model"],
                    "reasoning_effort": settings["reasoning_effort"],
                    "model_provider_id": settings["model_provider_id"],
                    "source_session_id": settings.get("source_session_id", ""),
                    "observed_at": settings.get("observed_at", ""),
                    "recorded_at": utc_now(),
                    "source": source,
                }
                atomic_write_json(pending_path, pending)
                result = {
                    "status": "staged",
                    "model": settings["model"],
                    "reasoning_effort": settings["reasoning_effort"],
                }
        atomic_write_json(
            status_path,
            {
                "schema_version": SCHEMA_VERSION,
                "profile_id": context.profile_id,
                "updated_at": utc_now(),
                **result,
            },
        )
        return result


def hook_input() -> dict[str, Any]:
    raw = sys.stdin.buffer.read(MAX_HOOK_INPUT_BYTES + 1)
    if len(raw) > MAX_HOOK_INPUT_BYTES:
        raise DefaultsError("hook input is too large")
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DefaultsError("invalid hook input") from exc
    if not isinstance(value, dict):
        raise DefaultsError("invalid hook input")
    return value


def cmd_hook() -> int:
    """Best effort by design: a persistence hook must never block a prompt."""
    try:
        context = launch_context()
        value = hook_input()
        event = value.get("hook_event_name") or value.get("hookEventName")
        if event not in {"UserPromptSubmit", "Stop"}:
            return 0
        transcript_value = value.get("transcript_path") or value.get("transcriptPath")
        if not isinstance(transcript_value, str):
            return 0
        transcript = allowed_transcript(transcript_value, context)
        settings = latest_settings(transcript, context)
        if settings is not None:
            session_id = value.get("session_id") or value.get("sessionId")
            if isinstance(session_id, str) and UUID_RE.fullmatch(session_id):
                settings["source_session_id"] = session_id.lower()
            stage_settings(context, settings, "hook")
    except (DefaultsError, OSError, ValueError):
        return 0
    return 0


def migration_candidates(context: LaunchContext) -> list[Path]:
    root = context.control_home / "sessions"
    if not root.is_dir():
        return []
    candidates = [
        path
        for path in root.rglob("*.jsonl")
        if path.is_file() and not path.is_symlink()
    ]
    candidates.sort(key=lambda path: path.stat().st_mtime_ns, reverse=True)
    return candidates[:MAX_MIGRATION_FILES]


def cmd_migrate_latest() -> int:
    context = launch_context()
    selected: dict[str, Any] | None = None
    for transcript in migration_candidates(context):
        settings = latest_settings(transcript, context)
        if settings is None:
            continue
        if selected is None or observed_order(settings["observed_at"]) > observed_order(
            selected["observed_at"]
        ):
            selected = settings
    if selected is None:
        emit(status="unchanged", reason="no-default-settings")
        return 0
    emit(**stage_settings(context, selected, "upgrade-migration"))
    return 0


def cmd_status() -> int:
    control_value = os.environ.get(
        "CODEX_FOR_TUI_CONTROL_HOME",
        str(Path(os.environ.get("HOME", "/root")) / ".codex"),
    )
    state = Path(control_value).expanduser().resolve() / "install-state" / "session-defaults"
    pending = sorted(path.stem for path in state.glob("p-*.json") if path.is_file())
    emit(status="ready", pending_profiles=pending)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="codex-session-defaults")
    parser.add_argument("command", choices=("hook", "migrate-latest", "status"))
    args = parser.parse_args()
    try:
        if args.command == "hook":
            return cmd_hook()
        if args.command == "migrate-latest":
            return cmd_migrate_latest()
        return cmd_status()
    except DefaultsError as exc:
        print(
            json.dumps(
                {"ok": False, "error": str(exc)},
                ensure_ascii=False,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
