#!/usr/bin/env python3
"""Transactional Codex workspace metadata migration.

Only rollout session_meta.cwd and SQLite threads.cwd are changed. Conversation
body bytes, UUIDs and rollout mtimes remain authoritative and unchanged.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import sqlite3
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterator


SCHEMA_VERSION = 1
MAX_FIRST_LINE_BYTES = 16 * 1024 * 1024
COPY_CHUNK_BYTES = 1024 * 1024


class MigrationError(Exception):
    def __init__(self, message: str, code: int = 70, **details: Any) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.details = details


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def emit(ok: bool, **payload: Any) -> None:
    print(json.dumps({"ok": ok, **payload}, ensure_ascii=False, sort_keys=True))


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)


def fsync_dir(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def atomic_write_bytes(path: Path, data: bytes, mode: int = 0o600) -> None:
    ensure_private_dir(path.parent)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        tmp.chmod(mode)
        os.replace(tmp, path)
        fsync_dir(path.parent)
    finally:
        tmp.unlink(missing_ok=True)


def atomic_write_json(path: Path, value: Any) -> None:
    atomic_write_bytes(
        path,
        (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(
            "utf-8"
        ),
    )


def atomic_copy_file(source: Path, destination: Path, mode: int) -> None:
    ensure_private_dir(destination.parent)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.tmp-", dir=destination.parent
    )
    tmp = Path(tmp_name)
    try:
        with source.open("rb") as current, os.fdopen(fd, "wb") as output:
            shutil.copyfileobj(current, output, COPY_CHUNK_BYTES)
            output.flush()
            os.fsync(output.fileno())
        tmp.chmod(mode)
        os.replace(tmp, destination)
        fsync_dir(destination.parent)
    finally:
        tmp.unlink(missing_ok=True)


def read_json(path: Path, default: Any = None) -> Any:
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MigrationError("无法读取工作区迁移元数据", path=str(path)) from exc


def hash_stream(handle: Any) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(COPY_CHUNK_BYTES), b""):
        digest.update(chunk)
    return digest.hexdigest()


def hash_path(path: Path) -> str:
    with path.open("rb") as handle:
        return hash_stream(handle)


def safe_relative(home: Path, path: Path) -> str:
    try:
        return str(path.resolve(strict=False).relative_to(home.resolve()))
    except ValueError as exc:
        raise MigrationError("迁移路径越过 CODEX_HOME", path=str(path)) from exc


def resolve_relative(home: Path, value: str) -> Path:
    candidate = (home / value).resolve(strict=False)
    try:
        candidate.relative_to(home.resolve())
    except ValueError as exc:
        raise MigrationError("备份路径越过 CODEX_HOME", path=value) from exc
    return candidate


@contextlib.contextmanager
def migration_lock(home: Path) -> Iterator[None]:
    lock = home / "install-state" / "workspace-migration.lock"
    ensure_private_dir(lock.parent)
    with lock.open("a+", encoding="utf-8") as handle:
        os.fchmod(handle.fileno(), 0o600)
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        yield


def maybe_failpoint(name: str) -> None:
    requested = os.environ.get("CODEX_WORKSPACE_MIGRATION_FAILPOINT", "")
    if requested == name:
        raise MigrationError("工作区迁移故障注入", 86, failpoint=name)
    if requested == f"crash:{name}":
        os._exit(86)


def rollout_entry(home: Path, path: Path) -> dict[str, Any] | None:
    if path.is_symlink() or not path.is_file():
        return None
    before = path.stat()
    with path.open("rb") as handle:
        first = handle.readline(MAX_FIRST_LINE_BYTES + 1)
        if len(first) > MAX_FIRST_LINE_BYTES or not first.endswith(b"\n"):
            return None
        try:
            value = json.loads(first)
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        payload = value.get("payload") if value.get("type") == "session_meta" else None
        if not isinstance(payload, dict) or not isinstance(payload.get("cwd"), str):
            return None
        session_id = str(payload.get("id") or payload.get("session_id") or "").strip()
        if not session_id:
            return None
        tail_digest = hashlib.sha256()
        full_digest = hashlib.sha256(first)
        for chunk in iter(lambda: handle.read(COPY_CHUNK_BYTES), b""):
            tail_digest.update(chunk)
            full_digest.update(chunk)
    return {
        "path": safe_relative(home, path),
        "session_id": session_id,
        "original_cwd": str(payload["cwd"]),
        "original_first_line_b64": base64.b64encode(first).decode("ascii"),
        "tail_sha256": tail_digest.hexdigest(),
        "full_sha256": full_digest.hexdigest(),
        "mode": stat.S_IMODE(before.st_mode),
        "atime_ns": before.st_atime_ns,
        "mtime_ns": before.st_mtime_ns,
        "size": before.st_size,
        "imported": False,
    }


def discover_rollouts(home: Path) -> list[dict[str, Any]]:
    root = home / "sessions"
    if not root.is_dir():
        return []
    result: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*.jsonl")):
        entry = rollout_entry(home, path)
        if entry is not None:
            result.append(entry)
    return result


def legacy_session_roots(home: Path) -> list[Path]:
    roots: list[Path] = []
    for parent in (home / "config-profiles", home / "config-runtimes"):
        if not parent.is_dir():
            continue
        for profile in sorted(parent.iterdir()):
            root = profile / "sessions"
            if root.is_dir() and not root.is_symlink():
                roots.append(root)
    return roots


def discover_legacy_imports(
    home: Path,
    control_rollouts: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    control_ids = {str(entry["session_id"]).lower() for entry in control_rollouts}
    imports: dict[str, dict[str, Any]] = {}
    for root in legacy_session_roots(home):
        for path in sorted(root.rglob("*.jsonl")):
            entry = rollout_entry(home, path)
            if entry is None:
                continue
            session_id = str(entry["session_id"]).lower()
            if session_id in control_ids:
                continue
            relative = path.relative_to(root)
            destination = home / "sessions" / relative
            source_path = str(entry["path"])
            entry["source_path"] = source_path
            entry["source_paths"] = [source_path]
            entry["path"] = safe_relative(home, destination)
            entry["imported"] = True
            previous = imports.get(session_id)
            if previous is None:
                imports[session_id] = entry
                continue
            if (
                previous["full_sha256"] != entry["full_sha256"]
                or previous["path"] != entry["path"]
            ):
                raise MigrationError(
                    "旧配置目录存在冲突的同 UUID rollout",
                    session_id=session_id,
                )
            previous["source_paths"].append(source_path)
            if int(entry["mtime_ns"]) > int(previous["mtime_ns"]):
                for key in ("mode", "atime_ns", "mtime_ns"):
                    previous[key] = entry[key]
    return [imports[key] for key in sorted(imports)]


def sqlite_candidates(home: Path) -> list[Path]:
    candidates = [home / "state_5.sqlite"]
    candidates.extend((home / "config-profiles").glob("**/state_5.sqlite"))
    candidates.extend(
        (home / "config-runtimes").glob("*/sqlite-builds/*/state_5.sqlite")
    )
    return sorted({path for path in candidates if path.is_file() and not path.is_symlink()})


def affected_thread_ids(path: Path, source: str) -> list[str]:
    try:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
        try:
            columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(threads)")
            }
            if not {"id", "cwd"}.issubset(columns):
                return []
            return [
                str(row[0])
                for row in connection.execute(
                    "SELECT id FROM threads WHERE cwd = ? ORDER BY id", (source,)
                )
            ]
        finally:
            connection.close()
    except sqlite3.Error:
        return []


def backup_sqlite(source: Path, destination: Path) -> None:
    ensure_private_dir(destination.parent)
    destination.unlink(missing_ok=True)
    src = sqlite3.connect(f"file:{source}?mode=ro", uri=True, timeout=10)
    dst = sqlite3.connect(destination)
    try:
        src.backup(dst)
        if dst.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise MigrationError("SQLite 备份完整性检查失败", path=str(source))
    finally:
        dst.close()
        src.close()
    destination.chmod(0o600)


def create_backup(
    home: Path,
    source: str,
    target: str,
    release: str,
    rollouts: list[dict[str, Any]],
    imports: list[dict[str, Any]],
) -> tuple[Path, dict[str, Any]]:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = home / "install-state" / "backups" / "workspace-migration" / (
        f"{stamp}-{release}"
    )
    ensure_private_dir(backup)
    sqlite_entries: list[dict[str, Any]] = []
    for index, path in enumerate(sqlite_candidates(home)):
        thread_ids = affected_thread_ids(path, source)
        if not thread_ids:
            continue
        before = path.stat()
        backup_name = f"{index:04d}-{hashlib.sha256(str(path).encode()).hexdigest()[:16]}.sqlite"
        backup_path = backup / "sqlite" / backup_name
        backup_sqlite(path, backup_path)
        sqlite_entries.append(
            {
                "path": safe_relative(home, path),
                "backup": str(backup_path.relative_to(backup)),
                "thread_ids": thread_ids,
                "mode": stat.S_IMODE(before.st_mode),
                "atime_ns": before.st_atime_ns,
                "mtime_ns": before.st_mtime_ns,
            }
        )
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "release": release,
        "source": source,
        "target": target,
        "created_at": utc_now(),
        "rollouts": rollouts,
        "imports": imports,
        "sqlite": sqlite_entries,
    }
    atomic_write_json(backup / "manifest.json", manifest)
    return backup, manifest


def ensure_migration_space(
    home: Path,
    rollouts: list[dict[str, Any]],
    imports: list[dict[str, Any]],
    source: str,
) -> None:
    largest_rollout = max((int(item["size"]) for item in rollouts), default=0)
    import_bytes = sum(int(item["size"]) for item in imports)
    sqlite_bytes = sum(
        path.stat().st_size
        for path in sqlite_candidates(home)
        if affected_thread_ids(path, source)
    )
    required = import_bytes + largest_rollout + sqlite_bytes + 32 * 1024 * 1024
    available = shutil.disk_usage(home).free
    if available < required:
        raise MigrationError(
            "工作区迁移可用空间不足",
            28,
            required_bytes=required,
            available_bytes=available,
        )


def copy_import_rollout(home: Path, entry: dict[str, Any]) -> None:
    source = resolve_relative(home, str(entry["source_path"]))
    destination = resolve_relative(home, str(entry["path"]))
    if destination.exists() or destination.is_symlink():
        raise MigrationError(
            "旧会话导入目标已存在",
            path=str(destination),
            session_id=str(entry["session_id"]),
        )
    ensure_private_dir(destination.parent)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.import-", dir=destination.parent
    )
    tmp = Path(tmp_name)
    digest = hashlib.sha256()
    try:
        with os.fdopen(fd, "wb") as output, source.open("rb") as current:
            for chunk in iter(lambda: current.read(COPY_CHUNK_BYTES), b""):
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        if digest.hexdigest() != entry["full_sha256"]:
            raise MigrationError(
                "旧会话在导入期间发生变化",
                path=str(source),
                session_id=str(entry["session_id"]),
            )
        tmp.chmod(int(entry["mode"]))
        os.replace(tmp, destination)
        os.utime(
            destination,
            ns=(int(entry["atime_ns"]), int(entry["mtime_ns"])),
        )
        fsync_dir(destination.parent)
    finally:
        tmp.unlink(missing_ok=True)


def replace_rollout_first_line(
    path: Path,
    original_first: bytes,
    source: str,
    target: str,
    mode: int,
    atime_ns: int,
    mtime_ns: int,
) -> None:
    source_json = json.dumps(source, ensure_ascii=False).encode("utf-8")
    target_json = json.dumps(target, ensure_ascii=False).encode("utf-8")
    pattern = re.compile(rb'("cwd"\s*:\s*)' + re.escape(source_json))
    updated, count = pattern.subn(
        lambda match: match.group(1) + target_json,
        original_first,
        count=1,
    )
    if count != 1:
        raise MigrationError("无法定位 rollout 工作区字段", path=str(path))
    try:
        parsed = json.loads(updated)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MigrationError("迁移后的 session_meta 无效", path=str(path)) from exc
    payload = parsed.get("payload") if parsed.get("type") == "session_meta" else None
    if not isinstance(payload, dict) or payload.get("cwd") != target:
        raise MigrationError("迁移后的 rollout 工作区校验失败", path=str(path))

    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.workspace-", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as output, path.open("rb") as current:
            current_first = current.readline(MAX_FIRST_LINE_BYTES + 1)
            if current_first != original_first:
                raise MigrationError("rollout 在迁移期间发生变化", path=str(path))
            output.write(updated)
            shutil.copyfileobj(current, output, COPY_CHUNK_BYTES)
            output.flush()
            os.fsync(output.fileno())
        tmp.chmod(mode)
        os.replace(tmp, path)
        os.utime(path, ns=(atime_ns, mtime_ns))
        fsync_dir(path.parent)
    finally:
        tmp.unlink(missing_ok=True)


def verify_rollout(home: Path, entry: dict[str, Any], target: str) -> None:
    path = resolve_relative(home, str(entry["path"]))
    with path.open("rb") as handle:
        first = handle.readline(MAX_FIRST_LINE_BYTES + 1)
        try:
            value = json.loads(first)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise MigrationError("无法验证迁移后的 rollout", path=str(path)) from exc
        payload = value.get("payload") if value.get("type") == "session_meta" else None
        if not isinstance(payload, dict) or payload.get("cwd") != target:
            raise MigrationError("rollout 工作区迁移未生效", path=str(path))
        session_id = str(payload.get("id") or payload.get("session_id") or "").strip()
        if session_id != str(entry["session_id"]):
            raise MigrationError("rollout UUID 在迁移期间发生变化", path=str(path))
        if hash_stream(handle) != entry["tail_sha256"]:
            raise MigrationError("rollout 对话正文发生变化", path=str(path))
    current = path.stat()
    if current.st_mtime_ns != int(entry["mtime_ns"]):
        raise MigrationError("rollout mtime 未保留", path=str(path))
    if stat.S_IMODE(current.st_mode) != int(entry["mode"]):
        raise MigrationError("rollout 权限位未保留", path=str(path))


def verify_import(
    home: Path,
    entry: dict[str, Any],
    source: str,
    target: str,
) -> None:
    path = resolve_relative(home, str(entry["path"]))
    if str(entry["original_cwd"]) == source:
        verify_rollout(home, entry, target)
        return
    if hash_path(path) != entry["full_sha256"]:
        raise MigrationError("导入的旧会话正文发生变化", path=str(path))
    current = path.stat()
    if current.st_mtime_ns != int(entry["mtime_ns"]):
        raise MigrationError("导入的旧会话 mtime 未保留", path=str(path))
    if stat.S_IMODE(current.st_mode) != int(entry["mode"]):
        raise MigrationError("导入的旧会话权限位未保留", path=str(path))


def migrate_sqlite(home: Path, entry: dict[str, Any], source: str, target: str) -> int:
    path = resolve_relative(home, str(entry["path"]))
    try:
        connection = sqlite3.connect(path, timeout=10)
        try:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                "UPDATE threads SET cwd = ? WHERE cwd = ?", (target, source)
            )
            changed = int(cursor.rowcount)
            connection.commit()
            if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
                raise MigrationError("迁移后 SQLite 完整性检查失败", path=str(path))
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()
    except sqlite3.Error as exc:
        raise MigrationError("无法迁移 SQLite 工作区元数据", path=str(path)) from exc
    expected = len(entry.get("thread_ids") or [])
    if changed != expected:
        raise MigrationError(
            "SQLite 迁移记录数不匹配",
            path=str(path),
            expected=expected,
            actual=changed,
        )
    return changed


def verify_sqlite(home: Path, entry: dict[str, Any], source: str, target: str) -> None:
    path = resolve_relative(home, str(entry["path"]))
    ids = [str(value) for value in entry.get("thread_ids") or []]
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
    try:
        source_count = int(
            connection.execute(
                "SELECT COUNT(*) FROM threads WHERE cwd = ?", (source,)
            ).fetchone()[0]
        )
        placeholders = ",".join("?" for _ in ids)
        target_count = (
            int(
                connection.execute(
                    f"SELECT COUNT(*) FROM threads WHERE id IN ({placeholders}) AND cwd = ?",
                    (*ids, target),
                ).fetchone()[0]
            )
            if ids
            else 0
        )
    finally:
        connection.close()
    if source_count != 0 or target_count != len(ids):
        raise MigrationError(
            "SQLite 工作区迁移验证失败",
            path=str(path),
            source_remaining=source_count,
            target_count=target_count,
        )


def restore_rollout(home: Path, entry: dict[str, Any]) -> None:
    path = resolve_relative(home, str(entry["path"]))
    if not path.is_file():
        if bool(entry.get("imported")):
            return
        raise MigrationError("rollout 回滚目标缺失", path=str(path))
    original = base64.b64decode(str(entry["original_first_line_b64"]), validate=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.rollback-", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as output, path.open("rb") as current:
            current.readline(MAX_FIRST_LINE_BYTES + 1)
            output.write(original)
            shutil.copyfileobj(current, output, COPY_CHUNK_BYTES)
            output.flush()
            os.fsync(output.fileno())
        tmp.chmod(int(entry["mode"]))
        os.replace(tmp, path)
        os.utime(path, ns=(int(entry["atime_ns"]), int(entry["mtime_ns"])))
        fsync_dir(path.parent)
    finally:
        tmp.unlink(missing_ok=True)


def restore_sqlite(home: Path, backup: Path, entry: dict[str, Any]) -> None:
    target = resolve_relative(home, str(entry["path"]))
    source = backup / str(entry["backup"])
    if not source.is_file():
        raise MigrationError("SQLite 回滚备份缺失", path=str(source))
    atomic_copy_file(source, target, int(entry["mode"]))
    target.with_name(target.name + "-wal").unlink(missing_ok=True)
    target.with_name(target.name + "-shm").unlink(missing_ok=True)
    os.utime(target, ns=(int(entry["atime_ns"]), int(entry["mtime_ns"])))


def remove_import(home: Path, entry: dict[str, Any]) -> None:
    path = resolve_relative(home, str(entry["path"]))
    if not path.exists() and not path.is_symlink():
        return
    if path.is_symlink() or not path.is_file():
        raise MigrationError("旧会话导入回滚目标类型异常", path=str(path))
    if hash_path(path) != entry["full_sha256"]:
        raise MigrationError(
            "旧会话导入回滚检测到新内容，已拒绝删除",
            path=str(path),
            session_id=str(entry["session_id"]),
        )
    path.unlink()
    fsync_dir(path.parent)


def validate_backup(home: Path, backup_value: str) -> tuple[Path, dict[str, Any]]:
    backup = Path(backup_value).expanduser().resolve()
    root = (home / "install-state" / "backups" / "workspace-migration").resolve()
    try:
        backup.relative_to(root)
    except ValueError as exc:
        raise MigrationError("工作区迁移备份路径无效", backup=str(backup)) from exc
    manifest = read_json(backup / "manifest.json")
    if not isinstance(manifest, dict) or manifest.get("schema_version") != SCHEMA_VERSION:
        raise MigrationError("工作区迁移备份损坏", backup=str(backup))
    return backup, manifest


def restore_backup(home: Path, backup: Path, manifest: dict[str, Any]) -> None:
    for entry in manifest.get("rollouts") or []:
        restore_rollout(home, entry)
    for entry in manifest.get("sqlite") or []:
        restore_sqlite(home, backup, entry)
    for entry in manifest.get("imports") or []:
        remove_import(home, entry)
    manifest["rolled_back_at"] = utc_now()
    atomic_write_json(backup / "manifest.json", manifest)


def recover_incomplete(home: Path) -> bool:
    journal_path = home / "install-state" / "workspace-migration.json"
    journal = read_json(journal_path)
    if not isinstance(journal, dict):
        return False
    backup, manifest = validate_backup(home, str(journal.get("backup", "")))
    restore_backup(home, backup, manifest)
    journal_path.unlink(missing_ok=True)
    return True


def cmd_migrate(args: argparse.Namespace) -> None:
    home = Path(args.codex_home).expanduser().resolve()
    source = str(Path(args.source))
    target = str(Path(args.target))
    if not Path(source).is_absolute() or not Path(target).is_absolute() or source == target:
        raise MigrationError("工作区迁移路径无效", 2)
    ensure_private_dir(home)
    with migration_lock(home):
        recovered = recover_incomplete(home)
        control_rollouts = discover_rollouts(home)
        imports = (
            discover_legacy_imports(home, control_rollouts)
            if args.import_legacy_runtimes
            else []
        )
        rollouts = [
            entry
            for entry in control_rollouts
            if str(entry["original_cwd"]) == source
        ]
        rollouts.extend(
            entry for entry in imports if str(entry["original_cwd"]) == source
        )
        sqlite_paths = [
            path for path in sqlite_candidates(home) if affected_thread_ids(path, source)
        ]
        if not rollouts and not imports and not sqlite_paths:
            emit(
                True,
                release=args.release,
                source=source,
                target=target,
                already_migrated=True,
                recovered_transaction=recovered,
                import_count=0,
                rollout_count=0,
                sqlite_count=0,
                thread_count=0,
                control_rollout_count=len(control_rollouts),
            )
            return
        ensure_migration_space(home, rollouts, imports, source)
        backup: Path | None = None
        journal_path = home / "install-state" / "workspace-migration.json"
        try:
            backup, manifest = create_backup(
                home, source, target, args.release, rollouts, imports
            )
            atomic_write_json(
                journal_path,
                {
                    "schema_version": SCHEMA_VERSION,
                    "release": args.release,
                    "backup": str(backup),
                    "phase": "prepared",
                    "started_at": utc_now(),
                },
            )
            maybe_failpoint("after-journal")
            for entry in manifest["imports"]:
                copy_import_rollout(home, entry)
            maybe_failpoint("after-imports")
            for entry in manifest["rollouts"]:
                replace_rollout_first_line(
                    resolve_relative(home, str(entry["path"])),
                    base64.b64decode(entry["original_first_line_b64"], validate=True),
                    source,
                    target,
                    int(entry["mode"]),
                    int(entry["atime_ns"]),
                    int(entry["mtime_ns"]),
                )
            maybe_failpoint("after-rollouts")
            changed_threads = 0
            for entry in manifest["sqlite"]:
                changed_threads += migrate_sqlite(home, entry, source, target)
            maybe_failpoint("after-sqlite")
            for entry in manifest["rollouts"]:
                verify_rollout(home, entry, target)
            for entry in manifest["imports"]:
                verify_import(home, entry, source, target)
            for entry in manifest["sqlite"]:
                verify_sqlite(home, entry, source, target)
            report = {
                "schema_version": SCHEMA_VERSION,
                "release": args.release,
                "source": source,
                "target": target,
                "completed_at": utc_now(),
                "backup": str(backup),
                "import_count": len(manifest["imports"]),
                "rollout_count": len(manifest["rollouts"]),
                "sqlite_count": len(manifest["sqlite"]),
                "thread_count": changed_threads,
                "control_rollout_count_before": len(control_rollouts),
                "control_rollout_count_after": len(control_rollouts)
                + len(manifest["imports"]),
                "recovered_transaction": recovered,
            }
            completion = (
                home / "install-state" / "workspace-migrations" / f"{args.release}.json"
            )
            atomic_write_json(completion, report)
            manifest["completed_at"] = report["completed_at"]
            atomic_write_json(backup / "manifest.json", manifest)
            journal_path.unlink(missing_ok=True)
            emit(True, **report)
        except BaseException:
            if backup is not None and (backup / "manifest.json").is_file():
                restore_backup(home, backup, read_json(backup / "manifest.json"))
            journal_path.unlink(missing_ok=True)
            raise


def cmd_rollback(args: argparse.Namespace) -> None:
    home = Path(args.codex_home).expanduser().resolve()
    with migration_lock(home):
        recover_incomplete(home)
        backup, manifest = validate_backup(home, args.backup)
        restore_backup(home, backup, manifest)
        release = str(manifest.get("release", ""))
        if release:
            (
                home / "install-state" / "workspace-migrations" / f"{release}.json"
            ).unlink(missing_ok=True)
        emit(
            True,
            release=release,
            backup=str(backup),
            import_count=len(manifest.get("imports") or []),
            rollout_count=len(manifest.get("rollouts") or []),
            sqlite_count=len(manifest.get("sqlite") or []),
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    migrate = sub.add_parser("migrate")
    migrate.add_argument("--from", dest="source", required=True)
    migrate.add_argument("--to", dest="target", required=True)
    migrate.add_argument("--release", required=True)
    migrate.add_argument("--import-legacy-runtimes", action="store_true")
    migrate.set_defaults(handler=cmd_migrate)
    rollback = sub.add_parser("rollback")
    rollback.add_argument("--backup", required=True)
    rollback.set_defaults(handler=cmd_rollback)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.handler(args)
        return 0
    except MigrationError as exc:
        emit(False, error=exc.message, code=exc.code, **exc.details)
        return exc.code
    except (OSError, sqlite3.Error, ValueError) as exc:
        emit(False, error="工作区迁移内部错误", code=70, detail=type(exc).__name__)
        return 70


if __name__ == "__main__":
    raise SystemExit(main())
