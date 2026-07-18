#!/usr/bin/env python3
"""Snapshot and verify Codex rollout history without printing transcript text."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import sqlite3
import stat
import sys
from pathlib import Path
from typing import Any


CHUNK_BYTES = 1024 * 1024
MAX_FIRST_LINE_BYTES = 16 * 1024 * 1024


class AuditError(Exception):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def emit(value: dict[str, Any]) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True))


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AuditError(f"invalid JSON metadata: {path}") from exc


def path_is_within(path: Path, root: Path) -> bool:
    """True if path is root or a descendant. Uses inode identity for proot dual paths."""
    try:
        path = path.expanduser().resolve()
        root = root.expanduser().resolve()
    except OSError:
        return False
    try:
        path.relative_to(root)
        return True
    except ValueError:
        pass
    try:
        if path == root or path.samefile(root):
            return True
    except OSError:
        pass
    current = path
    while True:
        parent = current.parent
        if parent == current:
            return False
        try:
            if parent.samefile(root):
                return True
        except OSError:
            pass
        current = parent


def rollout_record(home: Path, path: Path) -> dict[str, Any]:
    before = path.stat()
    with path.open("rb") as handle:
        first = handle.readline(MAX_FIRST_LINE_BYTES + 1)
        if len(first) > MAX_FIRST_LINE_BYTES or not first.endswith(b"\n"):
            raise AuditError(f"invalid rollout first line: {path}")
        try:
            value = json.loads(first)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise AuditError(f"invalid rollout JSON: {path}") from exc
        payload = value.get("payload") if value.get("type") == "session_meta" else None
        if not isinstance(payload, dict):
            raise AuditError(f"missing session_meta payload: {path}")
        session_id = str(payload.get("id") or payload.get("session_id") or "").strip()
        cwd = payload.get("cwd")
        if not session_id or not isinstance(cwd, str):
            raise AuditError(f"missing rollout UUID/cwd: {path}")
        tail = hashlib.sha256()
        full = hashlib.sha256(first)
        for chunk in iter(lambda: handle.read(CHUNK_BYTES), b""):
            tail.update(chunk)
            full.update(chunk)
    return {
        "id": session_id.lower(),
        "path": str(path.resolve().relative_to(home.resolve())),
        "cwd": cwd,
        "tail_sha256": tail.hexdigest(),
        "full_sha256": full.hexdigest(),
        "first_line_size": len(first),
        "tail_size": before.st_size - len(first),
        "mtime_ns": before.st_mtime_ns,
        "mode": stat.S_IMODE(before.st_mode),
        "size": before.st_size,
    }


def scan_root(home: Path, root: Path) -> list[dict[str, Any]]:
    if not root.is_dir():
        return []
    records = []
    for path in sorted(root.rglob("*.jsonl")):
        if path.is_symlink() or not path.is_file():
            continue
        records.append(rollout_record(home, path))
    return records


def unique_by_id(records: list[dict[str, Any]], label: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for record in records:
        session_id = str(record["id"])
        if session_id in result:
            raise AuditError(f"duplicate UUID in {label}: {session_id}")
        result[session_id] = record
    return result


def legacy_roots(home: Path) -> list[Path]:
    result = []
    for parent in (home / "config-profiles", home / "config-runtimes"):
        if not parent.is_dir():
            continue
        for profile in sorted(parent.iterdir()):
            root = profile / "sessions"
            if root.is_dir() and not root.is_symlink():
                result.append(root)
    return result


def snapshot(home: Path) -> dict[str, Any]:
    canonical = scan_root(home, home / "sessions")
    canonical_by_id = unique_by_id(canonical, "canonical sessions")
    legacy: dict[str, dict[str, Any]] = {}
    for root in legacy_roots(home):
        for record in scan_root(home, root):
            session_id = str(record["id"])
            if session_id in canonical_by_id:
                continue
            source_path = str(record["path"])
            relative = Path(source_path).relative_to(
                Path(str(root.resolve().relative_to(home.resolve())))
            )
            canonical_path = str(Path("sessions") / relative)
            previous = legacy.get(session_id)
            if previous is None:
                legacy[session_id] = {
                    **record,
                    "canonical_path": canonical_path,
                    "source_paths": [source_path],
                }
                continue
            if (
                previous["full_sha256"] != record["full_sha256"]
                or previous["canonical_path"] != canonical_path
            ):
                raise AuditError(f"conflicting legacy UUID: {session_id}")
            previous["source_paths"].append(source_path)
            if int(record["mtime_ns"]) > int(previous["mtime_ns"]):
                for key in ("mtime_ns", "mode"):
                    previous[key] = record[key]
    return {
        "schema_version": 1,
        "created_at": utc_now(),
        "canonical_count": len(canonical),
        "legacy_unique_count": len(legacy),
        "canonical": canonical,
        "legacy_unique": [legacy[key] for key in sorted(legacy)],
    }


def expected_cwd(record: dict[str, Any], source: str, target: str) -> str:
    return target if record["cwd"] == source else str(record["cwd"])


def tail_prefix_sha256(home: Path, record: dict[str, Any], size: int) -> str:
    path = (home / str(record["path"])).resolve()
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        handle.readline(MAX_FIRST_LINE_BYTES + 1)
        remaining = size
        while remaining:
            chunk = handle.read(min(CHUNK_BYTES, remaining))
            if not chunk:
                raise AuditError(f"rollout tail was truncated: {record['id']}")
            digest.update(chunk)
            remaining -= len(chunk)
    return digest.hexdigest()


def assert_body_and_mode(
    home: Path,
    now: dict[str, Any],
    baseline: dict[str, Any],
) -> None:
    now_mode = int(now["mode"])
    baseline_mode = int(baseline["mode"])
    owner_mask = stat.S_IRWXU
    if (
        (now_mode & owner_mask) != (baseline_mode & owner_mask)
        or now_mode & ~baseline_mode
    ):
        raise AuditError(f"rollout permission mode changed: {baseline['id']}")
    baseline_tail_size = int(baseline["tail_size"])
    current_tail_size = int(now["tail_size"])
    if current_tail_size < baseline_tail_size:
        raise AuditError(f"transcript body was truncated: {baseline['id']}")
    if (
        tail_prefix_sha256(home, now, baseline_tail_size)
        != baseline["tail_sha256"]
    ):
        raise AuditError(f"transcript body prefix changed: {baseline['id']}")


def assert_preserved(
    home: Path,
    current: dict[str, dict[str, Any]],
    baseline: dict[str, Any],
    source: str,
    target: str,
) -> tuple[int, int]:
    canonical = baseline.get("canonical")
    legacy = baseline.get("legacy_unique")
    if not isinstance(canonical, list) or not isinstance(legacy, list):
        raise AuditError("baseline does not contain canonical/legacy lists")
    for record in canonical:
        session_id = str(record["id"])
        now = current.get(session_id)
        if now is None:
            raise AuditError(f"baseline UUID missing after upgrade: {session_id}")
        if now["path"] != record["path"]:
            raise AuditError(f"baseline rollout path changed: {session_id}")
        assert_body_and_mode(home, now, record)
        if now["cwd"] != expected_cwd(record, source, target):
            raise AuditError(f"baseline rollout cwd mismatch: {session_id}")
    for record in legacy:
        session_id = str(record["id"])
        now = current.get(session_id)
        if now is None:
            raise AuditError(f"legacy UUID was not imported: {session_id}")
        if now["path"] != record["canonical_path"]:
            raise AuditError(f"legacy canonical path mismatch: {session_id}")
        assert_body_and_mode(home, now, record)
        if now["cwd"] != expected_cwd(record, source, target):
            raise AuditError(f"legacy rollout cwd mismatch: {session_id}")
        for source_value in record.get("source_paths") or []:
            source_path = (home / str(source_value))
            if not source_path.exists():
                # 2.5.16+ may replace private profile/runtime session trees
                # with a shared symlink. Their old copies may be absent once
                # the UUID is preserved in the control sessions inventory.
                if str(source_value).startswith(
                    ("config-runtimes/", "config-profiles/")
                ):
                    continue
                raise AuditError(f"legacy source missing: {session_id}: {source_value}")
            try:
                resolved = source_path.resolve()
            except OSError as exc:
                raise AuditError(f"legacy source unreadable: {session_id}") from exc
            if not path_is_within(resolved, home):
                raise AuditError("legacy source escaped CODEX_HOME")
            # Shared runtime sessions symlink intentionally resolves into the
            # control sessions tree (cwd-migrated body). Only assert byte-stable
            # private copies (config-profiles / real private trees).
            if _source_is_shared_sessions_view(home, source_path, resolved, now):
                continue
            source_now = rollout_record(home, source_path)
            if source_now["full_sha256"] != record["full_sha256"]:
                raise AuditError(f"legacy source copy changed: {session_id}")
    return len(canonical), len(legacy)


def _source_is_shared_sessions_view(
    home: Path,
    source_path: Path,
    resolved: Path,
    canonical_now: dict[str, Any],
) -> bool:
    """True when a baseline legacy source now views the shared control sessions file.

    After 2.5.16 session unity, config-runtimes/*/sessions is a symlink to
    control sessions. Reading that path yields the migrated canonical body, not
    the pre-import private copy — so full_sha256 must not be compared to the
    baseline private snapshot.
    """
    source_text = str(source_path)
    if "config-runtimes/" not in source_text and "config-profiles/" not in source_text:
        return False
    # Walk parents: if any sessions component is a symlink into control sessions.
    current = source_path
    control_sessions = home / "sessions"
    for _ in range(12):
        if current.name == "sessions":
            try:
                if current.is_symlink() and (
                    current.resolve() == control_sessions.resolve()
                    or current.resolve().samefile(control_sessions)
                ):
                    return True
            except OSError:
                return False
        parent = current.parent
        if parent == current:
            break
        current = parent
    # Also treat resolve identity with the live canonical path as a shared view
    # (covers proot dual roots where string paths differ but inodes match).
    try:
        canonical_path = home / str(canonical_now["path"])
        if resolved == canonical_path.resolve() or resolved.samefile(canonical_path):
            # Only skip when this is not a still-private profile/runtime file.
            # Private trees keep a real sessions directory; shared views do not.
            sessions_dir = source_path
            while sessions_dir.name != "sessions" and sessions_dir != sessions_dir.parent:
                sessions_dir = sessions_dir.parent
            if sessions_dir.name == "sessions" and sessions_dir.is_symlink():
                return True
    except (OSError, KeyError, TypeError):
        pass
    return False


def sqlite_candidates(home: Path) -> list[Path]:
    candidates = {home / "state_5.sqlite"}
    candidates.update((home / "config-profiles").glob("**/state_5.sqlite"))
    candidates.update(
        (home / "config-runtimes").glob("*/sqlite-builds/*/state_5.sqlite")
    )
    return sorted(
        path for path in candidates if path.is_file() and not path.is_symlink()
    )


def audit_sqlite(home: Path, source: str) -> tuple[int, int]:
    checked = 0
    thread_count = 0
    for path in sqlite_candidates(home):
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
        try:
            if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
                raise AuditError(f"SQLite quick_check failed: {path}")
            columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(threads)")
            }
            if not {"id", "cwd"}.issubset(columns):
                continue
            checked += 1
            thread_count += int(
                connection.execute("SELECT COUNT(*) FROM threads").fetchone()[0]
            )
            remaining = int(
                connection.execute(
                    "SELECT COUNT(*) FROM threads WHERE cwd = ?", (source,)
                ).fetchone()[0]
            )
            if remaining:
                raise AuditError(f"SQLite still contains source cwd: {path}")
        finally:
            connection.close()
    return checked, thread_count


def verify(args: argparse.Namespace) -> dict[str, Any]:
    home = Path(args.codex_home).expanduser().resolve()
    report_path = Path(args.release_report).expanduser().resolve()
    baseline = load_json(Path(args.baseline).expanduser().resolve())
    report = load_json(report_path)
    completion_path = (
        home / "install-state" / "workspace-migrations" / f"{args.release}.json"
    ).resolve()
    report_is_completion = report_path == completion_path
    if not report_is_completion:
        try:
            report_is_completion = report_path.samefile(completion_path)
        except OSError:
            pass
    if not isinstance(report, dict) or (
        report.get("ok") is not True and not report_is_completion
    ):
        raise AuditError("workspace migration report is not successful")
    for key, expected in (
        ("release", args.release),
        ("source", args.source),
        ("target", args.target),
        ("import_count", args.expected_import_count),
        ("rollout_count", args.expected_migrated_count),
    ):
        if report.get(key) != expected:
            raise AuditError(f"migration report mismatch: {key}")
    backup = Path(str(report.get("backup", ""))).expanduser()
    if not backup.is_absolute():
        backup = (home / backup).resolve()
    else:
        backup = backup.resolve()
    backup_root = (
        home / "install-state" / "backups" / "workspace-migration"
    ).resolve()
    if not path_is_within(backup, backup_root):
        # Proot often exposes the same inode as both /root/... and
        # /data/.../local/alpine/root/...; fall back to the home-relative path.
        alt = backup_root / backup.name
        if alt.is_dir() and path_is_within(alt, backup_root):
            backup = alt
        else:
            raise AuditError("migration backup escaped backup root")
    manifest = load_json(backup / "manifest.json")
    for key, expected in (
        ("schema_version", 1),
        ("release", args.release),
        ("source", args.source),
        ("target", args.target),
    ):
        if manifest.get(key) != expected:
            raise AuditError(f"migration backup manifest mismatch: {key}")
    if len(manifest.get("imports") or []) != args.expected_import_count:
        raise AuditError("migration backup import count mismatch")
    if len(manifest.get("rollouts") or []) != args.expected_migrated_count:
        raise AuditError("migration backup rollout count mismatch")
    completed = load_json(completion_path)
    for key in (
        "backup",
        "release",
        "source",
        "target",
        "import_count",
        "rollout_count",
        "sqlite_count",
        "thread_count",
    ):
        if completed.get(key) != report.get(key):
            raise AuditError(f"migration completion/report mismatch: {key}")

    current_records = scan_root(home, home / "sessions")
    current = unique_by_id(current_records, "post-upgrade canonical sessions")
    if any(record["cwd"] == args.source for record in current_records):
        raise AuditError("canonical rollout still contains source cwd")
    baseline_count, legacy_count = assert_preserved(
        home, current, baseline, args.source, args.target
    )
    if baseline_count != args.expected_baseline_count:
        raise AuditError("baseline canonical count mismatch")
    if len(current) < args.expected_min_count:
        raise AuditError("canonical rollout count below expected minimum")
    sqlite_count, sqlite_threads = audit_sqlite(home, args.source)
    return {
        "ok": True,
        "release": args.release,
        "canonical_count": len(current),
        "baseline_preserved": baseline_count,
        "legacy_imported": legacy_count,
        "migrated_rollouts": int(report["rollout_count"]),
        "sqlite_files_checked": sqlite_count,
        "sqlite_threads_checked": sqlite_threads,
        "backup_manifest": True,
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    take = commands.add_parser("snapshot")
    take.add_argument("--codex-home", required=True)
    check = commands.add_parser("verify")
    check.add_argument("--codex-home", required=True)
    check.add_argument("--release-report", required=True)
    check.add_argument("--baseline", required=True)
    check.add_argument("--release", required=True)
    check.add_argument("--source", default="/root")
    check.add_argument("--target", default="/root/workspace")
    check.add_argument("--expected-import-count", type=int, required=True)
    check.add_argument("--expected-migrated-count", type=int, required=True)
    check.add_argument("--expected-baseline-count", type=int, required=True)
    check.add_argument("--expected-min-count", type=int, required=True)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "snapshot":
            emit(snapshot(Path(args.codex_home).expanduser().resolve()))
        else:
            emit(verify(args))
        return 0
    except (AuditError, OSError, sqlite3.Error, ValueError) as exc:
        emit({"ok": False, "error": str(exc), "type": type(exc).__name__})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
