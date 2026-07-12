#!/usr/bin/env python3
"""Copy legacy Codex rollouts into the active runtime sessions tree.

Native Codex /resume reads $CODEX_HOME/sessions. In config-v2 mode that path is
the active profile runtime home. Old history often still lives under the control
home or other profile/runtime session trees. This importer is idempotent, never
deletes sources, and refuses to overwrite same-UUID different-content conflicts.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
UUID_RE = re.compile(
    r"(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
COPY_CHUNK = 1024 * 1024


class ImportError_(Exception):
    def __init__(self, message: str, code: int = 70, **details: Any) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.details = details


def utc_now() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def emit(ok: bool, **payload: Any) -> None:
    print(json.dumps({"ok": ok, **payload}, ensure_ascii=False, sort_keys=True))


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(COPY_CHUNK)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def extract_session_id(path: Path) -> str | None:
    try:
        with path.open("rb") as handle:
            first = handle.readline(16 * 1024 * 1024)
    except OSError:
        return None
    if not first:
        return None
    try:
        text = first.decode("utf-8")
    except UnicodeDecodeError:
        return None
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(value, dict):
        return None
    payload = value.get("payload")
    if isinstance(payload, dict):
        for key in ("id", "session_id"):
            candidate = payload.get(key)
            if isinstance(candidate, str) and UUID_RE.fullmatch(candidate.strip()):
                return candidate.strip().lower()
    for key in ("id", "session_id"):
        candidate = value.get(key)
        if isinstance(candidate, str) and UUID_RE.fullmatch(candidate.strip()):
            return candidate.strip().lower()
    # Fallback: UUID in filename.
    for part in path.stem.replace("_", "-").split("-"):
        pass
    match = re.search(
        r"(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        path.name,
    )
    if match:
        return match.group(0).lower()
    return None


def relative_date_path(path: Path, root: Path) -> Path | None:
    try:
        rel = path.relative_to(root)
    except ValueError:
        return None
    if rel.suffix != ".jsonl":
        return None
    return rel


def source_roots(control_home: Path, runtime_home: Path) -> list[Path]:
    roots: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        try:
            resolved = path.resolve(strict=False)
        except OSError:
            resolved = path
        key = str(resolved)
        if key in seen:
            return
        if not path.is_dir() or path.is_symlink():
            # Allow real dirs only; skip broken links and non-dirs.
            if path.is_symlink():
                try:
                    if not path.resolve().is_dir():
                        return
                except OSError:
                    return
            elif not path.is_dir():
                return
        seen.add(key)
        roots.append(path)

    add(control_home / "sessions")
    for parent_name in ("config-profiles", "config-runtimes"):
        parent = control_home / parent_name
        if not parent.is_dir():
            continue
        try:
            children = sorted(parent.iterdir())
        except OSError:
            continue
        for child in children:
            add(child / "sessions")
    # Never treat the destination itself as a source when it is a pure symlink
    # to control home; real private trees under other runtimes are still sources.
    dest = runtime_home / "sessions"
    try:
        dest_key = str(dest.resolve(strict=False))
    except OSError:
        dest_key = str(dest)
    return [root for root in roots if str(root.resolve(strict=False)) != dest_key]


def atomic_copy(source: Path, destination: Path) -> None:
    ensure_private_dir(destination.parent)
    mode = 0o600
    try:
        mode = source.stat().st_mode & 0o777
    except OSError:
        pass
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.tmp-", dir=str(destination.parent)
    )
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as out_handle, source.open("rb") as in_handle:
            shutil.copyfileobj(in_handle, out_handle, length=COPY_CHUNK)
            out_handle.flush()
            os.fsync(out_handle.fileno())
        try:
            st = source.stat()
            os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))
        except OSError:
            pass
        tmp.chmod(mode)
        os.replace(tmp, destination)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)


def import_sessions(
    control_home: Path,
    runtime_home: Path,
    journal_dir: Path | None = None,
) -> dict[str, Any]:
    control_home = control_home.expanduser()
    runtime_home = runtime_home.expanduser()
    if not control_home.is_dir():
        raise ImportError_("control home missing", control_home=str(control_home))
    if not runtime_home.is_dir():
        raise ImportError_("runtime home missing", runtime_home=str(runtime_home))

    dest_root = runtime_home / "sessions"
    ensure_private_dir(dest_root)

    if journal_dir is None:
        journal_dir = control_home / "install-state" / "runtime-session-import"
    ensure_private_dir(journal_dir)

    # Destination inventory by UUID and path.
    dest_by_uuid: dict[str, Path] = {}
    dest_hash_by_uuid: dict[str, str] = {}
    if dest_root.is_dir():
        for path in dest_root.rglob("*.jsonl"):
            if not path.is_file() or path.is_symlink():
                continue
            session_id = extract_session_id(path)
            if not session_id:
                continue
            dest_by_uuid[session_id] = path
            dest_hash_by_uuid[session_id] = sha256_file(path)

    copied = 0
    skipped_same = 0
    conflicts: list[dict[str, str]] = []
    scanned = 0
    sources_used: list[str] = []

    for root in source_roots(control_home, runtime_home):
        sources_used.append(str(root))
        for path in sorted(root.rglob("*.jsonl")):
            if not path.is_file() or path.is_symlink():
                continue
            scanned += 1
            session_id = extract_session_id(path)
            if not session_id:
                continue
            rel = relative_date_path(path, root)
            if rel is None:
                # Keep UUID identity even when date path is nonstandard.
                rel = Path(path.name)
            destination = dest_root / rel
            source_hash = sha256_file(path)

            existing = dest_by_uuid.get(session_id)
            if existing is not None:
                existing_hash = dest_hash_by_uuid.get(session_id) or sha256_file(existing)
                if existing_hash == source_hash:
                    skipped_same += 1
                    continue
                conflicts.append(
                    {
                        "session_id": session_id,
                        "source": str(path),
                        "destination": str(existing),
                        "reason": "same-uuid-different-bytes",
                    }
                )
                continue

            if destination.exists():
                # Different UUID already occupies the relative path: quarantine
                # the new file beside it instead of overwriting.
                alt = destination.with_name(
                    f"{destination.stem}.import-{session_id[:8]}{destination.suffix}"
                )
                destination = alt
                if destination.exists():
                    existing_hash = sha256_file(destination)
                    if existing_hash == source_hash:
                        skipped_same += 1
                        continue
                    conflicts.append(
                        {
                            "session_id": session_id,
                            "source": str(path),
                            "destination": str(destination),
                            "reason": "path-occupied",
                        }
                    )
                    continue

            atomic_copy(path, destination)
            dest_by_uuid[session_id] = destination
            dest_hash_by_uuid[session_id] = source_hash
            copied += 1

    result = {
        "schema_version": SCHEMA_VERSION,
        "control_home": str(control_home),
        "runtime_home": str(runtime_home),
        "destination": str(dest_root),
        "scanned": scanned,
        "copied": copied,
        "skipped_same": skipped_same,
        "conflicts": conflicts,
        "sources": sources_used,
        "finished_at": utc_now(),
    }
    journal_path = journal_dir / f"{runtime_home.name}.json"
    journal_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    try:
        journal_path.chmod(0o600)
    except OSError:
        pass
    result["journal"] = str(journal_path)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-home", required=True)
    parser.add_argument("--runtime-home", required=True)
    parser.add_argument("--journal-dir")
    args = parser.parse_args(argv)
    try:
        result = import_sessions(
            Path(args.control_home),
            Path(args.runtime_home),
            Path(args.journal_dir) if args.journal_dir else None,
        )
        emit(True, **result)
        return 0
    except ImportError_ as exc:
        emit(False, error=exc.message, code=exc.code, **exc.details)
        return exc.code
    except Exception as exc:  # pragma: no cover - defensive
        emit(False, error=str(exc), code=1)
        return 1


if __name__ == "__main__":
    sys.exit(main())
