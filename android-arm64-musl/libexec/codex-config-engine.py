#!/usr/bin/env python3
"""Transactional Codex for TUI configuration/profile engine.

The shell scripts own prompts and presentation. This helper owns structured
TOML/JSON reads, profile identity, atomic commits, migration and model metadata.
Every command emits one JSON object and never prints secrets.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Iterator


SCRIPT_DIR = Path(__file__).resolve().parent
VENDOR_DIR = SCRIPT_DIR.parent / "vendor" / "python"
if VENDOR_DIR.is_dir():
    sys.path.insert(0, str(VENDOR_DIR))

try:
    import tomlkit
    from tomlkit import TOMLDocument, table
except ImportError as exc:  # pragma: no cover - exercised by install guards.
    raise SystemExit(f"missing bundled tomlkit: {exc}")


SCHEMA_VERSION = 2
OFFICIAL_CATALOG_URL = ""
PROFILE_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
PROFILE_ID_RE = re.compile(r"^p-[0-9a-f]{12}$")
PROFILE_GENERATION_RE = re.compile(r"^[0-9a-f]{64}$")
SQLITE_BUILD_KEY_RE = re.compile(r"^[A-Za-z0-9._-]+$")
MANAGED_PROVIDER_ID_RE = re.compile(r"^codex_tui_[0-9a-f]{12}$")
MANAGED_ROOT_KEYS = (
    "model_provider",
    "model",
    "model_reasoning_effort",
    "model_catalog_json",
)
RUNTIME_LOCAL_FILE = "runtime-local.toml"
COMMON_BASE_FILE = "common-base.toml"
RUNTIME_GENERATED_ROOT_KEYS = {
    "sqlite_home",
    "model_auto_compact_token_limit",
    "model_providers",
}


class EngineError(Exception):
    def __init__(self, message: str, code: int = 70, **details: Any) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.details = details


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def emit(ok: bool, **payload: Any) -> None:
    result = {"ok": ok, **payload}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


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


def atomic_write_text(path: Path, text: str, mode: int = 0o600) -> None:
    atomic_write_bytes(path, text.encode("utf-8"), mode)


def atomic_write_json(path: Path, value: Any, mode: int = 0o600) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    atomic_write_text(path, text, mode)


def read_json(path: Path, default: Any = None) -> Any:
    if not path.is_file():
        return copy.deepcopy(default)
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise EngineError(f"无法读取 JSON：{path.name}", 70, path=str(path)) from exc


def read_toml(path: Path) -> TOMLDocument:
    if not path.is_file():
        return tomlkit.document()
    try:
        return tomlkit.parse(path.read_text(encoding="utf-8"))
    except (OSError, Exception) as exc:
        raise EngineError(f"无法解析 TOML：{path}", 7, path=str(path)) from exc


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_copy(src: Path, dst: Path, mode: int | None = None) -> None:
    try:
        data = src.read_bytes()
    except OSError as exc:
        raise EngineError(f"无法读取文件：{src}", 7, path=str(src)) from exc
    source_mode = stat.S_IMODE(src.stat().st_mode)
    atomic_write_bytes(dst, data, mode if mode is not None else source_mode)


def optional_files_equal(left: Path, right: Path) -> bool:
    if not left.exists() and not right.exists():
        return True
    if not left.is_file() or not right.is_file():
        return False
    return left.read_bytes() == right.read_bytes()


def maybe_failpoint(name: str) -> None:
    requested = os.environ.get("CODEX_CONFIG_FAILPOINT", "")
    if requested == name:
        raise EngineError("配置引擎故障注入", 86, failpoint=name)
    if requested == f"crash:{name}":
        os._exit(86)


class Paths:
    def __init__(self, codex_home: Path) -> None:
        self.home = codex_home
        self.config = codex_home / "config.toml"
        self.auth = codex_home / "auth.json"
        self.catalog = codex_home / "model_catalog.json"
        self.official_marker = codex_home / "install-state" / "official-login-mode"
        self.legacy_profiles_root = codex_home / "config-profiles"
        self.profiles_root = codex_home / "config-profiles-v2"
        self.index = self.profiles_root / "index.json"
        self.profiles = self.profiles_root / "profiles"
        self.drafts = self.profiles_root / "drafts"
        self.transactions = self.profiles_root / "transactions"
        self.runtimes = codex_home / "config-runtimes"
        self.lock = codex_home / "install-state" / "config-v2.lock"
        self.journal = codex_home / "install-state" / "config-v2-transaction.json"
        self.backups = codex_home / "install-state" / "backups" / "config-v2"
        self.v1_backups = codex_home / "install-state" / "config-v1-backups"
        self.v2_rollbacks = codex_home / "install-state" / "config-v2-rollbacks"
        self.catalog_cache = codex_home / "model-catalog-cache"
        self.auth_helper = codex_home / "print-openai-api-key.sh"
        self.session_defaults = codex_home / "install-state" / "session-defaults"

    def ensure_v2_dirs(self) -> None:
        ensure_private_dir(self.home)
        for path in (
            self.profiles_root,
            self.profiles,
            self.drafts,
            self.transactions,
            self.backups,
            self.catalog_cache,
            self.runtimes,
        ):
            ensure_private_dir(path)


def default_index() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "active_profile_id": None,
        "compact_policy": {"mode": "follow-model"},
        "runtime_managed": {"provider_id": None, "root_keys": []},
        "migration": {"v1_completed": False, "legacy_backup": None},
    }


def load_index(paths: Paths, create: bool = False) -> dict[str, Any]:
    value = read_json(paths.index, default_index())
    if value is None:
        value = default_index()
    if value.get("schema_version") != SCHEMA_VERSION:
        raise EngineError("配置档结构版本不受支持", 7)
    if create and not paths.index.exists():
        paths.ensure_v2_dirs()
        atomic_write_json(paths.index, value)
    return value


@contextlib.contextmanager
def engine_lock(paths: Paths) -> Iterator[None]:
    ensure_private_dir(paths.lock.parent)
    with paths.lock.open("a+", encoding="utf-8") as handle:
        os.fchmod(handle.fileno(), 0o600)
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        except OSError as exc:
            raise EngineError("无法锁定配置引擎", 5) from exc
        yield


def profile_dir(paths: Paths, profile_id: str) -> Path:
    if not PROFILE_ID_RE.fullmatch(profile_id):
        raise EngineError("配置 ID 无效", 2, profile_id=profile_id)
    return paths.profiles / profile_id


def default_runtime_home(paths: Paths, profile_id: str) -> Path:
    if not PROFILE_ID_RE.fullmatch(profile_id):
        raise EngineError("配置 ID 无效", 2, profile_id=profile_id)
    return paths.runtimes / profile_id


def runtime_home_for_profile(paths: Paths, meta: dict[str, Any]) -> Path:
    profile_id = str(meta.get("id", ""))
    configured = meta.get("runtime_home")
    runtime_home = (
        Path(configured)
        if isinstance(configured, str) and configured.strip()
        else default_runtime_home(paths, profile_id)
    )
    if not runtime_home.is_absolute():
        runtime_home = paths.home / runtime_home
    resolved_home = paths.home.resolve(strict=False)
    resolved_runtime = runtime_home.resolve(strict=False)
    try:
        resolved_runtime.relative_to(resolved_home)
    except ValueError as exc:
        raise EngineError(
            "配置运行目录必须位于 CODEX_HOME 内",
            7,
            runtime_home=str(runtime_home),
        ) from exc
    # Reject nested runtimes such as:
    #   $CODEX_HOME/config-runtimes/p-xxx/config-runtimes/p-yyy
    # which appear when CODEX_HOME was already a runtime path.
    try:
        relative = resolved_runtime.relative_to(resolved_home)
    except ValueError:
        relative = Path()
    parts = relative.parts
    if parts.count("config-runtimes") > 1:
        raise EngineError(
            "配置运行目录禁止连环嵌套",
            7,
            runtime_home=str(runtime_home),
        )
    if "config-runtimes" in parts:
        idx = parts.index("config-runtimes")
        # Expect config-runtimes/<profile-id>[/...]
        if idx + 1 >= len(parts) or not PROFILE_ID_RE.fullmatch(parts[idx + 1]):
            raise EngineError(
                "配置运行目录路径无效",
                7,
                runtime_home=str(runtime_home),
            )
    return resolved_runtime


def profile_meta(paths: Paths, profile_id: str) -> dict[str, Any]:
    directory = profile_dir(paths, profile_id)
    meta = read_json(directory / "profile.json")
    if not isinstance(meta, dict):
        raise EngineError("配置档不存在", 4, profile_id=profile_id)
    if (
        meta.get("schema_version") != SCHEMA_VERSION
        or meta.get("id") != profile_id
        or not isinstance(meta.get("name"), str)
        or not PROFILE_NAME_RE.fullmatch(str(meta["name"]))
        or meta.get("mode") not in ("official", "third_party")
    ):
        raise EngineError("配置档元数据损坏", 7, profile_id=profile_id)
    return meta


def list_profiles(paths: Paths) -> list[dict[str, Any]]:
    if not paths.profiles.is_dir():
        return []
    values: list[dict[str, Any]] = []
    for directory in sorted(paths.profiles.iterdir()):
        if not directory.is_dir() or not PROFILE_ID_RE.fullmatch(directory.name):
            continue
        values.append(profile_meta(paths, directory.name))
    return sorted(values, key=lambda item: (str(item.get("name", "")).lower(), item.get("id", "")))


def validate_profile_name(name: str) -> str:
    value = name.strip()
    if not value or not PROFILE_NAME_RE.fullmatch(value):
        raise EngineError("配置名称只能使用字母、数字、点、下划线和短横线", 2)
    return value


def resolve_profile(paths: Paths, ref: str) -> dict[str, Any]:
    ref = ref.strip()
    if PROFILE_ID_RE.fullmatch(ref):
        return profile_meta(paths, ref)
    matches = [item for item in list_profiles(paths) if item.get("name") == ref]
    if not matches:
        raise EngineError("配置档不存在", 4, profile=ref)
    if len(matches) > 1:
        raise EngineError("配置名称不唯一，请使用配置 ID", 5, profile=ref)
    return matches[0]


def ensure_unique_name(paths: Paths, name: str, except_id: str | None = None) -> None:
    for item in list_profiles(paths):
        if item.get("name") == name and item.get("id") != except_id:
            raise EngineError("同名配置已存在", 3, profile=name, profile_id=item.get("id"))


def new_profile_id() -> str:
    return "p-" + uuid.uuid4().hex[:12]


def provider_id_for(profile_id: str) -> str:
    return "codex_tui_" + profile_id.removeprefix("p-")


def normalize_base_url(value: str) -> str:
    cleaned = value.strip().rstrip("/")
    if not cleaned or any(ord(char) < 32 for char in cleaned):
        raise EngineError("API Base URL 无效", 2)
    try:
        parsed = urllib.parse.urlsplit(cleaned)
        _ = parsed.port
    except ValueError as exc:
        raise EngineError("API Base URL 无效", 2) from exc
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise EngineError("API Base URL 必须是 http(s) URL", 2)
    if parsed.username is not None or parsed.password is not None:
        raise EngineError("API Base URL 不能包含用户名或密码", 2)
    if parsed.query or parsed.fragment:
        raise EngineError("API Base URL 不能包含查询参数或片段", 2)
    return cleaned


def write_auth_helper(paths: Paths) -> None:
    script = """#!/usr/bin/env sh
set -eu
auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
if command -v jq >/dev/null 2>&1; then
  jq -r '.OPENAI_API_KEY // empty' "$auth"
else
  sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' "$auth" | sed -n '1p'
fi
"""
    atomic_write_text(paths.auth_helper, script, 0o700)


def build_managed_document(
    paths: Paths,
    profile_id: str,
    provider_name: str,
    base_url: str,
    model: str,
    reasoning_effort: str | None,
) -> TOMLDocument:
    doc = tomlkit.document()
    doc["model"] = model
    if reasoning_effort:
        doc["model_reasoning_effort"] = reasoning_effort
    provider = table()
    provider["name"] = provider_name
    provider["base_url"] = base_url
    provider["wire_api"] = "responses"
    provider["requires_openai_auth"] = False
    auth = table()
    auth["command"] = str(paths.auth_helper)
    auth["args"] = []
    auth["timeout_ms"] = 5000
    auth["refresh_interval_ms"] = 300000
    auth["cwd"] = str(paths.home)
    provider["auth"] = auth
    doc["provider"] = provider
    doc["provider_id"] = provider_id_for(profile_id)
    return doc


def managed_summary(directory: Path) -> dict[str, Any]:
    managed = read_toml(directory / "managed.toml")
    provider = managed.get("provider", {})
    return {
        "model": str(managed.get("model", "")),
        "reasoning_effort": (
            str(managed["model_reasoning_effort"])
            if "model_reasoning_effort" in managed
            else None
        ),
        "provider_id": str(managed.get("provider_id", "")),
        "provider_name": str(provider.get("name", "")) if provider else "",
        "base_url": str(provider.get("base_url", "")) if provider else "",
    }


def profile_generation(directory: Path) -> str:
    managed_path = directory / "managed.toml"
    try:
        data = managed_path.read_bytes()
    except OSError as exc:
        raise EngineError("配置档托管字段缺失", 7, path=str(managed_path)) from exc
    return hashlib.sha256(data).hexdigest()


def redact_profile(paths: Paths, meta: dict[str, Any]) -> dict[str, Any]:
    result = dict(meta)
    # compact_policy is global (index only). Never surface a stale per-profile copy.
    result.pop("compact_policy", None)
    directory = profile_dir(paths, str(meta["id"]))
    result.update(managed_summary(directory))
    result["has_auth"] = (directory / "auth.json").is_file()
    result["has_catalog"] = (directory / "model_catalog.json").is_file()
    result["generation"] = profile_generation(directory)
    return result


def snapshot_state(paths: Paths, label: str) -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = paths.backups / f"{stamp}-{label}"
    ensure_private_dir(backup)
    for source, name in (
        (paths.config, "config.toml"),
        (paths.auth, "auth.json"),
        (paths.catalog, "model_catalog.json"),
        (paths.official_marker, "official-login-mode"),
        (paths.index, "index.json"),
    ):
        if source.is_file():
            safe_copy(source, backup / name, 0o600)
    atomic_write_json(
        backup / "snapshot.json",
        {"schema_version": 1, "created_at": utc_now(), "label": label},
    )
    if paths.profiles_root.is_dir():
        shutil.copytree(paths.profiles_root, backup / "config-profiles")
    return backup


def restore_snapshot(paths: Paths, backup: Path) -> None:
    if paths.profiles_root.exists():
        shutil.rmtree(paths.profiles_root)
    source_root = backup / "config-profiles"
    if source_root.is_dir():
        shutil.copytree(source_root, paths.profiles_root)
    else:
        paths.ensure_v2_dirs()
        source_profiles = backup / "profiles"
        if source_profiles.is_dir():
            shutil.copytree(source_profiles, paths.profiles, dirs_exist_ok=True)
    for target, name in (
        (paths.config, "config.toml"),
        (paths.auth, "auth.json"),
        (paths.catalog, "model_catalog.json"),
        (paths.official_marker, "official-login-mode"),
        (paths.index, "index.json"),
    ):
        source = backup / name
        if source.is_file():
            safe_copy(source, target, 0o600)
        else:
            target.unlink(missing_ok=True)


def remove_snapshot(backup: Path) -> None:
    if backup.exists():
        shutil.rmtree(backup)


def recover_transaction(paths: Paths) -> bool:
    journal = read_json(paths.journal)
    if not isinstance(journal, dict):
        return False
    backup_value = journal.get("backup")
    backup = Path(backup_value) if isinstance(backup_value, str) else None
    if journal.get("phase") == "committed":
        if backup is not None and not journal.get("retain_backup"):
            remove_snapshot(backup)
        paths.journal.unlink(missing_ok=True)
        return False
    if backup is None:
        raise EngineError("事务日志损坏，无法自动恢复", 70)
    if not backup.is_dir():
        raise EngineError("事务备份缺失，无法自动恢复", 70, backup=str(backup))
    if journal.get("kind") == "v1-migration":
        restore_v1_backup(paths, backup)
    else:
        restore_snapshot(paths, backup)
    paths.journal.unlink(missing_ok=True)
    remove_snapshot(backup)
    return True


@contextlib.contextmanager
def transaction(paths: Paths, action: str, *, retain_backup: bool = False) -> Iterator[Path]:
    backup = snapshot_state(paths, action)
    atomic_write_json(
        paths.journal,
        {
            "schema_version": 1,
            "action": action,
            "phase": "prepared",
            "backup": str(backup),
            "retain_backup": retain_backup,
            "started_at": utc_now(),
        },
    )
    maybe_failpoint("after-journal-prepared")
    try:
        yield backup
    except BaseException:
        restore_snapshot(paths, backup)
        paths.journal.unlink(missing_ok=True)
        remove_snapshot(backup)
        raise
    else:
        journal = read_json(paths.journal, {})
        journal["phase"] = "committed"
        journal["committed_at"] = utc_now()
        atomic_write_json(paths.journal, journal)
        if not retain_backup:
            remove_snapshot(backup)
        paths.journal.unlink(missing_ok=True)


def replace_directory(staged: Path, destination: Path) -> None:
    old = destination.parent / f".old-{destination.name}-{uuid.uuid4().hex}"
    if destination.exists():
        os.replace(destination, old)
    try:
        os.replace(staged, destination)
    except Exception:
        if old.exists():
            os.replace(old, destination)
        raise
    if old.exists():
        shutil.rmtree(old)
    fsync_dir(destination.parent)


def sanitize_service_tier(doc: TOMLDocument | dict[str, Any]) -> bool:
    """Remove invalid service_tier values. Returns True if the doc changed.

    OpenAI service tiers are empty or "priority". Values like "high" are
    reasoning-effort names that some configs incorrectly store as service_tier;
    third-party relays then reject the request.
    """
    if not isinstance(doc, dict) and not hasattr(doc, "get"):
        return False
    if "service_tier" not in doc:
        return False
    value = doc.get("service_tier")
    if value is None:
        doc.pop("service_tier", None)
        return True
    text = str(value).strip().lower()
    if text in ("", "priority"):
        if text == "":
            doc.pop("service_tier", None)
            return True
        return False
    # Anything else (high/flex/default/...) is not a valid service tier here.
    doc.pop("service_tier", None)
    return True


def strip_managed_fields(
    doc: TOMLDocument,
    *,
    previous_provider: str | None = None,
) -> TOMLDocument:
    """Return a copy of doc with profile-variable / runtime-only fields removed.

    Common defaults live in the remaining document. Profile materialization
    re-applies managed variables as a patch instead of replaying a full snapshot.
    """
    cleaned = copy.deepcopy(doc)
    cleaned.pop("sqlite_home", None)
    for key in MANAGED_ROOT_KEYS:
        cleaned.pop(key, None)
    # compact threshold is owned by global compact_policy, not profile snapshots
    cleaned.pop("model_auto_compact_token_limit", None)
    # service_tier is not a station-specific setting; invalid values break krill.
    sanitize_service_tier(cleaned)
    # model_providers are station-owned (API/base_url/key). Never keep them in
    # common defaults, or orphan entries like [model_providers.custom] leak
    # across stations and reappear in every runtime materialization.
    cleaned.pop("model_providers", None)
    return cleaned


def write_profile_base_config(source: Path, destination: Path) -> None:
    """Persist a non-managed snapshot for migration/backup only (not materialize base)."""
    if not source.is_file():
        return
    doc = strip_managed_fields(read_toml(source))
    atomic_write_text(destination, tomlkit.dumps(doc), 0o600)


def load_common_config(paths: Paths, index: dict[str, Any] | None = None) -> TOMLDocument:
    """Load control-home common defaults with managed variables stripped."""
    runtime_managed = (index or {}).get("runtime_managed") if isinstance(index, dict) else None
    previous_provider = None
    if isinstance(runtime_managed, dict):
        previous_provider = runtime_managed.get("provider_id")
        if previous_provider is not None:
            previous_provider = str(previous_provider)
    if paths.config.is_file():
        return strip_managed_fields(read_toml(paths.config), previous_provider=previous_provider)
    return tomlkit.document()


def inherit_workspace_trust(
    doc: TOMLDocument,
    source: str = "/root",
    destination: str = "/root/workspace",
) -> bool:
    """Narrowly inherit an explicit trusted parent for the unified workspace."""
    projects = doc.get("projects")
    if not isinstance(projects, dict):
        return False
    source_entry = projects.get(source)
    if not isinstance(source_entry, dict) or source_entry.get("trust_level") != "trusted":
        return False
    destination_entry = projects.get(destination)
    if destination_entry is None:
        destination_entry = table()
        projects[destination] = destination_entry
    if not isinstance(destination_entry, dict) or "trust_level" in destination_entry:
        return False
    destination_entry["trust_level"] = "trusted"
    return True


def merge_runtime_local_overlay(doc: TOMLDocument, overlay: TOMLDocument | None) -> None:
    """Apply only explicitly tracked runtime-local keys."""
    if overlay is None:
        return
    for key in list(overlay):
        if key in MANAGED_ROOT_KEYS or key in RUNTIME_GENERATED_ROOT_KEYS:
            continue
        doc[key] = copy.deepcopy(overlay[key])


def extract_runtime_local_overlay(
    runtime: TOMLDocument,
    current_common: TOMLDocument,
    previous_common: TOMLDocument | None = None,
) -> TOMLDocument:
    """Keep only keys that are genuinely runtime-local.

    Keys present in the previous common snapshot are control-owned. If the user
    deletes one from control config.toml while an old runtime still contains it,
    automatic runtime sync must not stage it as local overlay and resurrect it.
    """
    runtime_clean = strip_managed_fields(runtime)
    current_clean = strip_managed_fields(current_common)
    previous_clean = (
        strip_managed_fields(previous_common)
        if previous_common is not None
        else tomlkit.document()
    )
    overlay = tomlkit.document()
    for key in list(runtime_clean):
        if key in MANAGED_ROOT_KEYS or key in RUNTIME_GENERATED_ROOT_KEYS:
            continue
        if key in current_clean or key in previous_clean:
            continue
        overlay[key] = copy.deepcopy(runtime_clean[key])
    return overlay


def write_runtime_local_overlay(directory: Path, overlay: TOMLDocument) -> None:
    destination = directory / RUNTIME_LOCAL_FILE
    if len(overlay) == 0:
        destination.unlink(missing_ok=True)
        return
    atomic_write_text(destination, tomlkit.dumps(overlay), 0o600)


def preserve_runtime_metadata(
    paths: Paths,
    profile_id: str,
    staged: Path,
) -> None:
    existing = profile_dir(paths, profile_id)
    for name in (RUNTIME_LOCAL_FILE, COMMON_BASE_FILE):
        source = existing / name
        if source.is_file():
            safe_copy(source, staged / name, 0o600)


def create_profile_directory(
    paths: Paths,
    *,
    profile_id: str,
    name: str,
    mode: str,
    provider_name: str,
    base_url: str,
    model: str,
    reasoning_effort: str | None,
    compatibility_model: str | None,
    auth_file: Path | None,
    catalog_file: Path | None,
    base_config_file: Path | None = None,
    existing_created_at: str | None = None,
    runtime_home: Path | None = None,
    compact_policy: dict[str, Any] | None = None,
) -> Path:
    staged = paths.profiles_root / f".profile-{profile_id}-{uuid.uuid4().hex}"
    ensure_private_dir(staged)
    now = utc_now()
    # Station meta only: identity + mode + runtime path.
    # Compact / context / permissions are global (index + control config.toml).
    _ = compact_policy  # retained for call-site compatibility; never stored per-station
    meta = {
        "schema_version": SCHEMA_VERSION,
        "id": profile_id,
        "name": name,
        "mode": mode,
        "compatibility_model": compatibility_model,
        "runtime_home": str(runtime_home or default_runtime_home(paths, profile_id)),
        "created_at": existing_created_at or now,
        "updated_at": now,
    }
    atomic_write_json(staged / "profile.json", meta)
    if base_config_file is not None:
        write_profile_base_config(base_config_file, staged / "legacy-config.toml")
        write_profile_base_config(base_config_file, staged / COMMON_BASE_FILE)
    if mode == "third_party":
        if not model:
            raise EngineError("默认模型不能为空", 2)
        normalized_base_url = normalize_base_url(base_url)
        managed = build_managed_document(
            paths,
            profile_id,
            provider_name or "OpenAI",
            normalized_base_url,
            model,
            reasoning_effort,
        )
        atomic_write_text(staged / "managed.toml", tomlkit.dumps(managed))
    else:
        managed = tomlkit.document()
        if model:
            managed["model"] = model
        if reasoning_effort:
            managed["model_reasoning_effort"] = reasoning_effort
        atomic_write_text(staged / "managed.toml", tomlkit.dumps(managed))
    if auth_file is not None and not auth_file.is_file():
        raise EngineError("认证文件不存在", 4, path=str(auth_file))
    if catalog_file is not None and not catalog_file.is_file():
        raise EngineError("模型目录文件不存在", 4, path=str(catalog_file))
    if auth_file:
        safe_copy(auth_file, staged / "auth.json", 0o600)
    if catalog_file:
        safe_copy(catalog_file, staged / "model_catalog.json", 0o600)
        meta_file = catalog_file.with_suffix(catalog_file.suffix + ".meta.json")
        if meta_file.is_file():
            safe_copy(meta_file, staged / "catalog.meta.json", 0o600)
    return staged


def compact_policy_from_config(config_file: Path | None) -> dict[str, Any]:
    if config_file is None or not config_file.is_file():
        return {"mode": "follow-model"}
    doc = read_toml(config_file)
    value = doc.get("model_auto_compact_token_limit")
    if isinstance(value, int) and value > 0 and value != 220000:
        return {"mode": "fixed", "value": value}
    return {"mode": "follow-model"}


def profile_compact_policy(
    meta: dict[str, Any] | None,
    index: dict[str, Any],
) -> dict[str, Any]:
    """Compact policy is global (index). Profile meta is ignored on purpose.

    `meta` is retained for call-site compatibility only.
    """
    _ = meta
    policy = index.get("compact_policy")
    if not isinstance(policy, dict):
        return {"mode": "follow-model"}
    if policy.get("mode") == "fixed":
        value = policy.get("value")
        if isinstance(value, int) and value > 0:
            return {"mode": "fixed", "value": value}
    return {"mode": "follow-model"}


def apply_compact_policy(
    doc: TOMLDocument,
    index: dict[str, Any],
    meta: dict[str, Any] | None = None,
) -> None:
    policy = profile_compact_policy(meta, index)
    runtime_managed = index.setdefault("runtime_managed", {"provider_id": None, "root_keys": []})
    owned = set(runtime_managed.get("root_keys") or [])
    if policy.get("mode") == "fixed":
        value = policy.get("value")
        if not isinstance(value, int) or value <= 0:
            raise EngineError("固定压缩阈值无效", 7)
        doc["model_auto_compact_token_limit"] = value
        owned.add("model_auto_compact_token_limit")
    else:
        doc.pop("model_auto_compact_token_limit", None)
        owned.discard("model_auto_compact_token_limit")
    runtime_managed["root_keys"] = sorted(owned)


def materialize_profile(paths: Paths, meta: dict[str, Any], index: dict[str, Any]) -> None:
    directory = profile_dir(paths, str(meta["id"]))
    # Drop stale per-station compact_policy if an older build wrote it.
    if isinstance(meta, dict) and "compact_policy" in meta:
        meta = dict(meta)
        meta.pop("compact_policy", None)
        atomic_write_json(directory / "profile.json", meta)
    # Common defaults from control home, then patch managed profile variables.
    # legacy-config.toml is migration/backup only and is never the materialize base.
    doc = load_common_config(paths, index)
    runtime_managed = index.setdefault("runtime_managed", {"provider_id": None, "root_keys": []})
    previous_provider = runtime_managed.get("provider_id")
    previous_keys = set(runtime_managed.get("root_keys") or [])

    mode = meta.get("mode")
    new_owned: set[str] = set()
    new_provider: str | None = None
    if mode == "third_party":
        managed = read_toml(directory / "managed.toml")
        provider = managed.get("provider")
        new_provider = str(managed.get("provider_id", ""))
        if not new_provider or provider is None:
            raise EngineError("配置档 Provider 数据不完整", 7)
        write_auth_helper(paths)
        doc["model_provider"] = new_provider
        doc["model"] = str(managed.get("model", ""))
        new_owned.update(("model_provider", "model"))
        if "model_reasoning_effort" in managed:
            doc["model_reasoning_effort"] = str(managed["model_reasoning_effort"])
            new_owned.add("model_reasoning_effort")
        # Stations only own their managed provider. Replace the whole table so
        # leftover custom/other station providers cannot survive activation.
        providers = table()
        providers[new_provider] = copy.deepcopy(provider)
        doc["model_providers"] = providers
        source_auth = directory / "auth.json"
        if source_auth.is_file():
            safe_copy(source_auth, paths.auth, 0o600)
        else:
            paths.auth.unlink(missing_ok=True)
        source_catalog = directory / "model_catalog.json"
        if source_catalog.is_file():
            write_catalog_with_visibility_policy(source_catalog, paths.catalog)
            doc["model_catalog_json"] = str(paths.catalog)
            new_owned.add("model_catalog_json")
        else:
            paths.catalog.unlink(missing_ok=True)
        paths.official_marker.unlink(missing_ok=True)
    elif mode == "official":
        managed = read_toml(directory / "managed.toml")
        model = str(managed.get("model", ""))
        if model:
            doc["model"] = model
            new_owned.add("model")
        if "model_reasoning_effort" in managed:
            doc["model_reasoning_effort"] = str(managed["model_reasoning_effort"])
            new_owned.add("model_reasoning_effort")
        source_auth = directory / "auth.json"
        if source_auth.is_file():
            safe_copy(source_auth, paths.auth, 0o600)
        else:
            paths.auth.unlink(missing_ok=True)
        paths.catalog.unlink(missing_ok=True)
        atomic_write_text(paths.official_marker, "official-login\n")
    else:
        raise EngineError("配置档模式无效", 7)

    runtime_managed["provider_id"] = new_provider
    runtime_managed["root_keys"] = sorted(new_owned | (previous_keys - set(MANAGED_ROOT_KEYS)))
    apply_compact_policy(doc, index, meta)
    atomic_write_text(paths.config, tomlkit.dumps(doc), 0o600)
    maybe_failpoint("after-runtime-config-write")
    index["active_profile_id"] = meta["id"]
    atomic_write_json(paths.index, index)


def runtime_matches_profile(paths: Paths, meta: dict[str, Any]) -> tuple[bool, list[str]]:
    directory = profile_dir(paths, str(meta["id"]))
    doc = read_toml(paths.config)
    managed = read_toml(directory / "managed.toml")
    reasons: list[str] = []
    mode = meta.get("mode")
    expected_model = str(managed.get("model", ""))
    expected_effort = (
        str(managed["model_reasoning_effort"])
        if "model_reasoning_effort" in managed
        else None
    )
    if expected_model and str(doc.get("model", "")) != expected_model:
        reasons.append("model")
    actual_effort = str(doc["model_reasoning_effort"]) if "model_reasoning_effort" in doc else None
    if actual_effort != expected_effort:
        reasons.append("model_reasoning_effort")
    if not optional_files_equal(directory / "auth.json", paths.auth):
        reasons.append("auth")

    if mode == "third_party":
        provider_id = str(managed.get("provider_id", ""))
        if str(doc.get("model_provider", "")) != provider_id:
            reasons.append("model_provider")
        expected_provider = managed.get("provider") or {}
        providers = doc.get("model_providers") or {}
        actual_provider = providers.get(provider_id) if provider_id else None
        for key in ("name", "base_url", "wire_api", "requires_openai_auth"):
            if actual_provider is None or actual_provider.get(key) != expected_provider.get(key):
                reasons.append(f"provider.{key}")
        expected_auth = expected_provider.get("auth") or {}
        actual_auth = actual_provider.get("auth") if actual_provider is not None else None
        for key in ("command", "args", "timeout_ms", "refresh_interval_ms", "cwd"):
            if actual_auth is None or actual_auth.get(key) != expected_auth.get(key):
                reasons.append(f"provider.auth.{key}")
        if not optional_files_equal(directory / "model_catalog.json", paths.catalog):
            reasons.append("catalog")
        expected_catalog_path = (
            str(paths.catalog) if (directory / "model_catalog.json").is_file() else None
        )
        actual_catalog_path = (
            str(doc["model_catalog_json"]) if "model_catalog_json" in doc else None
        )
        if actual_catalog_path != expected_catalog_path:
            reasons.append("model_catalog_json")
        if paths.official_marker.exists():
            reasons.append("official_marker")
    elif mode == "official":
        if "model_provider" in doc:
            reasons.append("model_provider")
        if "model_catalog_json" in doc:
            reasons.append("model_catalog_json")
        if not paths.official_marker.is_file():
            reasons.append("official_marker")
    else:
        reasons.append("mode")
    return not reasons, reasons


def cmd_profile_list(paths: Paths, _args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        index = load_index(paths)
        profiles = [redact_profile(paths, item) for item in list_profiles(paths)]
    emit(
        True,
        active_profile_id=index.get("active_profile_id"),
        compact_policy=profile_compact_policy(None, index),
        profiles=profiles,
    )


def cmd_profile_show(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        meta = resolve_profile(paths, args.profile)
        index = load_index(paths)
        profile = redact_profile(paths, meta)
    emit(
        True,
        active=meta["id"] == index.get("active_profile_id"),
        # Global compact policy for menu display (not a station field).
        compact_policy=profile_compact_policy(None, index),
        profile=profile,
    )


def cmd_profile_create(paths: Paths, args: argparse.Namespace) -> None:
    name = validate_profile_name(args.name)
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        ensure_unique_name(paths, name)
        profile_id = new_profile_id()
        with transaction(paths, "profile-create"):
            staged = create_profile_directory(
                paths,
                profile_id=profile_id,
                name=name,
                mode=args.mode,
                provider_name=args.provider_name,
                base_url=args.base_url or "",
                model=args.model or "",
                reasoning_effort=args.reasoning_effort,
                compatibility_model=args.compatibility_model,
                auth_file=Path(args.auth_file) if args.auth_file else None,
                catalog_file=Path(args.catalog_file) if args.catalog_file else None,
                base_config_file=paths.config if paths.config.is_file() else None,
                runtime_home=default_runtime_home(paths, profile_id),
            )
            replace_directory(staged, profile_dir(paths, profile_id))
            maybe_failpoint("after-profile-replace")
            index = load_index(paths, create=True)
            if args.activate:
                materialize_profile(paths, profile_meta(paths, profile_id), index)
        emit(True, profile=redact_profile(paths, profile_meta(paths, profile_id)))


def cmd_profile_update(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        current = resolve_profile(paths, args.profile)
        directory = profile_dir(paths, current["id"])
        summary = managed_summary(directory)
        name = validate_profile_name(args.name or str(current["name"]))
        ensure_unique_name(paths, name, str(current["id"]))
        mode = args.mode or str(current.get("mode", "third_party"))
        auth_file = Path(args.auth_file) if args.auth_file else (directory / "auth.json")
        catalog_file = Path(args.catalog_file) if args.catalog_file else (directory / "model_catalog.json")
        with transaction(paths, "profile-update"):
            staged = create_profile_directory(
                paths,
                profile_id=str(current["id"]),
                name=name,
                mode=mode,
                provider_name=args.provider_name or summary.get("provider_name") or "OpenAI",
                base_url=args.base_url or summary.get("base_url") or "",
                model=args.model or summary.get("model") or "",
                reasoning_effort=(
                    args.reasoning_effort
                    if args.reasoning_effort is not None
                    else summary.get("reasoning_effort")
                ),
                compatibility_model=(
                    args.compatibility_model
                    if args.compatibility_model is not None
                    else current.get("compatibility_model")
                ),
                auth_file=auth_file if auth_file.is_file() else None,
                catalog_file=catalog_file if catalog_file.is_file() else None,
                base_config_file=(
                    directory / "legacy-config.toml"
                    if (directory / "legacy-config.toml").is_file()
                    else (paths.config if paths.config.is_file() else None)
                ),
                existing_created_at=str(current.get("created_at", "")) or None,
                runtime_home=runtime_home_for_profile(paths, current),
                compact_policy=profile_compact_policy(current, load_index(paths, create=True)),
            )
            preserve_runtime_metadata(paths, str(current["id"]), staged)
            replace_directory(staged, directory)
            maybe_failpoint("after-profile-replace")
            index = load_index(paths, create=True)
            if index.get("active_profile_id") == current["id"]:
                materialize_profile(paths, profile_meta(paths, str(current["id"])), index)
        pending_session_defaults_path(paths, str(current["id"])).unlink(missing_ok=True)
        emit(True, profile=redact_profile(paths, profile_meta(paths, str(current["id"]))))


def cmd_profile_rename(paths: Paths, args: argparse.Namespace) -> None:
    args.name = args.new_name
    args.mode = None
    args.provider_name = None
    args.base_url = None
    args.model = None
    args.reasoning_effort = None
    args.compatibility_model = None
    args.auth_file = None
    args.catalog_file = None
    cmd_profile_update(paths, args)


def cmd_profile_activate(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        meta = resolve_profile(paths, args.profile)
        with transaction(paths, "profile-activate"):
            index = load_index(paths, create=True)
            materialize_profile(paths, meta, index)
        emit(True, profile=redact_profile(paths, meta), active=True)


# Shared conversation roots that must survive profile delete. They are usually
# symlinks from each runtime into control CODEX_HOME; never follow/unlink them
# in a way that wipes the control-home targets.
_SHARED_RUNTIME_LINK_NAMES = (
    "sessions",
    "archived_sessions",
    "history.jsonl",
    "shell_snapshots",
)


def _safe_remove_runtime_home(paths: Paths, runtime_home: Path) -> None:
    """Remove a profile runtime tree without destroying shared sessions.

    Prefer rmtree only when the runtime is a real directory distinct from
    control home. Shared link names are unlinked first (symlink only) so a
    subsequent rmtree cannot follow them into control CODEX_HOME.
    """
    if not runtime_home.exists() and not runtime_home.is_symlink():
        return
    try:
        if runtime_home.resolve() == paths.home.resolve():
            return
    except OSError:
        return

    # Drop shared conversation links first so rmtree never walks into them.
    for name in _SHARED_RUNTIME_LINK_NAMES:
        link = runtime_home / name
        try:
            if link.is_symlink() or link.is_file():
                link.unlink(missing_ok=True)
            elif link.is_dir():
                # Real dir copies of shared state are rare; leave them alone so
                # we never delete conversation history as a side effect.
                continue
        except OSError:
            continue

    if runtime_home.is_symlink():
        runtime_home.unlink(missing_ok=True)
        return
    if not runtime_home.is_dir():
        runtime_home.unlink(missing_ok=True)
        return
    try:
        shutil.rmtree(runtime_home, ignore_errors=True)
    except OSError:
        for runtime_file in (
            runtime_home / "config.toml",
            runtime_home / "auth.json",
            runtime_home / "model_catalog.json",
            runtime_home / "install-state" / "official-login-mode",
        ):
            runtime_file.unlink(missing_ok=True)


def cmd_profile_delete(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        meta = resolve_profile(paths, args.profile)
        index = load_index(paths, create=True)
        if index.get("active_profile_id") == meta["id"] and not args.allow_active:
            raise EngineError("不能直接删除当前配置，请先切换或显式允许保留运行配置", 5)
        runtime_home = runtime_home_for_profile(paths, meta)
        with transaction(paths, "profile-delete"):
            shutil.rmtree(profile_dir(paths, str(meta["id"])))
            # Drop runtime disk (sqlite epochs, catalogs) without touching shared
            # conversation state. sessions/history/etc. are often symlinks into
            # control CODEX_HOME — never follow those links.
            _safe_remove_runtime_home(paths, runtime_home)
            if index.get("active_profile_id") == meta["id"]:
                index["active_profile_id"] = None
                atomic_write_json(paths.index, index)
        pending_session_defaults_path(paths, str(meta["id"])).unlink(missing_ok=True)
        emit(True, deleted_profile_id=meta["id"], deleted_name=meta["name"])


def import_runtime_profile(
    paths: Paths,
    *,
    name: str,
    source_dir: Path,
    profile_id: str | None = None,
    existing_meta: dict[str, Any] | None = None,
    runtime_home: Path | None = None,
) -> dict[str, Any]:
    config = source_dir / "config.toml"
    auth = source_dir / "auth.json"
    catalog = source_dir / "model_catalog.json"
    marker = source_dir / "install-state" / "official-login-mode"
    doc = read_toml(config)
    mode = (
        "official"
        if marker.is_file() or not str(doc.get("model_provider", "")).strip()
        else "third_party"
    )
    profile_id = profile_id or new_profile_id()
    provider_name = "OpenAI"
    base_url = ""
    model = str(doc.get("model", ""))
    effort = str(doc["model_reasoning_effort"]) if "model_reasoning_effort" in doc else None
    if mode == "third_party":
        provider_id = str(doc.get("model_provider", ""))
        providers = doc.get("model_providers") or {}
        provider = providers.get(provider_id) if provider_id else None
        if provider:
            provider_name = str(provider.get("name", "OpenAI"))
            base_url = str(provider.get("base_url", ""))
        if not base_url or not model:
            raise EngineError("旧配置缺少 Provider、Base URL 或模型，无法自动导入", 7)
    staged = create_profile_directory(
        paths,
        profile_id=profile_id,
        name=name,
        mode=mode,
        provider_name=provider_name,
        base_url=base_url,
        model=model,
        reasoning_effort=effort,
        compatibility_model=None,
        auth_file=auth if auth.is_file() else None,
        catalog_file=catalog if catalog.is_file() else None,
        base_config_file=config if config.is_file() else None,
        existing_created_at=(
            str(existing_meta.get("created_at", "")) or None
            if existing_meta is not None
            else None
        ),
        runtime_home=(
            runtime_home
            or (
                runtime_home_for_profile(paths, existing_meta)
                if existing_meta is not None
                else default_runtime_home(paths, profile_id)
            )
        ),
        compact_policy=(
            {"mode": "follow-model"}
        ),
    )
    if existing_meta is not None:
        meta_path = staged / "profile.json"
        updated_meta = read_json(meta_path, {})
        updated_meta["compatibility_model"] = existing_meta.get("compatibility_model")
        atomic_write_json(meta_path, updated_meta)
        preserve_runtime_metadata(paths, profile_id, staged)
    replace_directory(staged, profile_dir(paths, profile_id))
    return profile_meta(paths, profile_id)


def cmd_profile_import(paths: Paths, args: argparse.Namespace) -> None:
    name = validate_profile_name(args.name)
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        ensure_unique_name(paths, name)
        with transaction(paths, "profile-import"):
            meta = import_runtime_profile(paths, name=name, source_dir=paths.home)
            if args.activate:
                index = load_index(paths, create=True)
                materialize_profile(paths, meta, index)
        emit(True, profile=redact_profile(paths, meta))


def cmd_profile_sync_current(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        current = resolve_profile(paths, args.profile)
        with transaction(paths, "profile-sync-current"):
            meta = import_runtime_profile(
                paths,
                name=str(current["name"]),
                source_dir=paths.home,
                profile_id=str(current["id"]),
                existing_meta=current,
            )
            index = load_index(paths, create=True)
            if index.get("active_profile_id") == current["id"]:
                materialize_profile(paths, meta, index)
        pending_session_defaults_path(paths, str(current["id"])).unlink(missing_ok=True)
        emit(True, profile=redact_profile(paths, meta))


def seed_runtime_links(paths: Paths, runtime_home: Path) -> None:
    """Link shared conversation state + managed docs into a profile runtime.

    Config/auth/sqlite stay per-runtime (isolated). Sessions/history are shared
    across profiles so switching model_providers / config profiles keeps one
    conversation list (user expectation for Codex for TUI).
    """
    if runtime_home == paths.home:
        return
    # Shared conversation state under control CODEX_HOME.
    seed_runtime_state(paths.home, runtime_home)
    for name in ("AGENTS.md", "skills", "rules"):
        source = paths.home / name
        destination = runtime_home / name
        if destination.exists() or destination.is_symlink() or not source.exists():
            continue
        try:
            destination.symlink_to(source, target_is_directory=source.is_dir())
        except OSError:
            continue


def pending_session_defaults_path(paths: Paths, profile_id: str) -> Path:
    return paths.session_defaults / f"{profile_id}.json"


def profile_catalog_for_defaults(paths: Paths, meta: dict[str, Any]) -> dict[str, Any]:
    directory = profile_dir(paths, str(meta["id"]))
    candidate = directory / "model_catalog.json"
    if not candidate.is_file():
        candidate = bundled_catalog_path()
    return validate_catalog(read_json(candidate))


def validate_profile_selection(
    paths: Paths,
    meta: dict[str, Any],
    model_value: Any,
    effort_value: Any,
    provider_value: Any,
) -> tuple[str, str | None]:
    model = model_value
    effort = effort_value
    if not isinstance(model, str) or not model.strip():
        raise EngineError("会话默认模型无效", 7, reason="invalid-model")
    model = model.strip()
    if effort is not None and (not isinstance(effort, str) or not effort.strip()):
        raise EngineError("会话默认推理等级无效", 7, reason="invalid-reasoning")
    effort = effort.strip() if isinstance(effort, str) else None

    summary = managed_summary(profile_dir(paths, str(meta["id"])))
    expected_provider = str(summary.get("provider_id") or "")
    provider_id = provider_value if isinstance(provider_value, str) else ""
    if expected_provider and provider_id != expected_provider:
        raise EngineError("会话 Provider 与配置档不匹配", 7, reason="provider-mismatch")

    catalog = profile_catalog_for_defaults(paths, meta)
    model_entry = catalog_by_slug(catalog).get(model)
    if model_entry is None:
        raise EngineError("会话模型不在当前目录中", 7, reason="model-not-in-catalog")
    levels = {
        str(item.get("effort"))
        for item in model_entry.get("supported_reasoning_levels", [])
        if isinstance(item, dict) and isinstance(item.get("effort"), str)
    }
    if effort is not None and effort not in levels:
        raise EngineError("模型不支持该推理等级", 7, reason="reasoning-not-supported")
    return model, effort


def apply_pending_session_defaults(
    paths: Paths,
    meta: dict[str, Any],
) -> tuple[dict[str, Any] | None, Path | None]:
    """Apply a hook-staged model/effort only against its launch generation."""
    profile_id = str(meta["id"])
    pending_path = pending_session_defaults_path(paths, profile_id)
    if not pending_path.is_file():
        return None, None
    try:
        pending = read_json(pending_path)
    except EngineError:
        return {"status": "rejected", "reason": "invalid-json"}, pending_path
    if not isinstance(pending, dict) or pending.get("schema_version") != 1:
        return {"status": "rejected", "reason": "invalid-schema"}, pending_path
    if pending.get("profile_id") != profile_id:
        return {"status": "rejected", "reason": "profile-mismatch"}, pending_path

    directory = profile_dir(paths, profile_id)
    current_generation = profile_generation(directory)
    base_generation = pending.get("base_generation")
    if (
        not isinstance(base_generation, str)
        or not PROFILE_GENERATION_RE.fullmatch(base_generation)
        or base_generation != current_generation
    ):
        return {"status": "rejected", "reason": "stale-generation"}, pending_path

    managed = read_toml(directory / "managed.toml")
    try:
        model, effort = validate_profile_selection(
            paths,
            meta,
            pending.get("model"),
            pending.get("reasoning_effort"),
            pending.get("model_provider_id"),
        )
    except EngineError as exc:
        return {
            "status": "rejected",
            "reason": str(exc.details.get("reason") or "invalid-selection"),
        }, pending_path

    previous_model = str(managed.get("model") or "")
    previous_effort = (
        str(managed["model_reasoning_effort"])
        if "model_reasoning_effort" in managed
        else None
    )
    if previous_model == model and previous_effort == effort:
        return {"status": "unchanged", "model": model, "reasoning_effort": effort}, pending_path
    managed["model"] = model
    if effort is None:
        managed.pop("model_reasoning_effort", None)
    else:
        managed["model_reasoning_effort"] = effort
    atomic_write_text(directory / "managed.toml", tomlkit.dumps(managed), 0o600)
    return {
        "status": "applied",
        "model": model,
        "reasoning_effort": effort,
        "previous_model": previous_model,
        "previous_reasoning_effort": previous_effort,
    }, pending_path


def materialize_runtime(
    paths: Paths,
    meta: dict[str, Any],
    index: dict[str, Any],
    sqlite_build_key: str,
) -> tuple[Path, Path]:
    if not SQLITE_BUILD_KEY_RE.fullmatch(sqlite_build_key):
        raise EngineError("Codex 构建标识无效", 2, sqlite_build_key=sqlite_build_key)
    materialize_profile(paths, meta, index)
    runtime_home = runtime_home_for_profile(paths, meta)
    sqlite_home = runtime_home / "sqlite-builds" / sqlite_build_key
    ensure_private_dir(runtime_home)
    ensure_private_dir(sqlite_home)
    seed_runtime_links(paths, runtime_home)
    # Repair idle runtimes too so switching profiles always sees the shared list.
    seed_all_runtime_states(paths)

    runtime_config = runtime_home / "config.toml"
    runtime_auth = runtime_home / "auth.json"
    runtime_catalog = runtime_home / "model_catalog.json"
    runtime_marker = runtime_home / "install-state" / "official-login-mode"

    previous_runtime = read_toml(runtime_config) if runtime_config.is_file() else None
    profile_directory = profile_dir(paths, str(meta["id"]))
    runtime_local_path = profile_directory / RUNTIME_LOCAL_FILE
    common_base_path = profile_directory / COMMON_BASE_FILE
    if not common_base_path.is_file():
        common_base_path = profile_directory / "legacy-config.toml"
    previous_common = (
        read_toml(common_base_path)
        if common_base_path.is_file()
        else tomlkit.document()
    )
    if runtime_local_path.is_file():
        runtime_local = read_toml(runtime_local_path)
    elif previous_runtime is not None:
        runtime_local = extract_runtime_local_overlay(previous_runtime, previous_common)
    else:
        runtime_local = tomlkit.document()
    # Keys present in the prior common snapshot remain control-owned. If the
    # user deletes one from control config.toml, a stale runtime-local overlay
    # must not resurrect it during the next materialization.
    previous_common_clean = strip_managed_fields(previous_common)
    for key in list(previous_common_clean):
        runtime_local.pop(key, None)
    doc = read_toml(paths.config)
    current_common_clean = strip_managed_fields(doc)
    for key in list(current_common_clean):
        runtime_local.pop(key, None)
    write_runtime_local_overlay(profile_directory, runtime_local)
    if paths.catalog.is_file():
        fixed_compact_policy = profile_compact_policy(meta, index).get("mode") == "fixed"
        write_catalog_with_visibility_policy(
            paths.catalog,
            runtime_catalog,
            fixed_compact_policy=fixed_compact_policy,
        )
        doc["model_catalog_json"] = str(runtime_catalog)
    else:
        runtime_catalog.unlink(missing_ok=True)
        doc.pop("model_catalog_json", None)
    doc["sqlite_home"] = str(sqlite_home)
    # Apply only explicitly tracked runtime-local extras; common control keys are authoritative.
    merge_runtime_local_overlay(doc, runtime_local)
    # Drop unsupported OpenAI service_tier values. Catalogs only expose
    # "priority" (or empty); "high"/"flex"/etc. cause relay errors on krill.
    sanitize_service_tier(doc)
    atomic_write_text(runtime_config, tomlkit.dumps(doc), 0o600)
    # Keep control home free of the same invalid tier so materialize stays clean.
    if paths.config.is_file():
        control_doc = read_toml(paths.config)
        if sanitize_service_tier(control_doc):
            atomic_write_text(paths.config, tomlkit.dumps(control_doc), 0o600)
    write_profile_base_config(paths.config, profile_directory / COMMON_BASE_FILE)

    if paths.auth.is_file():
        safe_copy(paths.auth, runtime_auth, 0o600)
    else:
        runtime_auth.unlink(missing_ok=True)
    if paths.official_marker.is_file():
        safe_copy(paths.official_marker, runtime_marker, 0o600)
    else:
        runtime_marker.unlink(missing_ok=True)
    # Native /resume filters by active model_provider_id, and Codex startup
    # backfill reloads threads from rollout session_meta. Codex++-style dual
    # sync rewrites shared session_meta + every runtime SQLite so the full
    # inventory stays visible without --all across stations.
    # Fast path: skip full dual-sync when marker already matches this provider.
    sync_provider_visibility(paths, runtime_home=runtime_home, fast=True)
    return runtime_home, sqlite_home


def cmd_profile_launch(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        index = load_index(paths, create=True)
        profile_ref = args.profile or index.get("active_profile_id")
        if not profile_ref:
            raise EngineError("当前没有已激活配置", 4)
        meta = resolve_profile(paths, str(profile_ref))
        pending_result: dict[str, Any] | None = None
        consumed_pending: Path | None = None
        with transaction(paths, "profile-launch"):
            pending_result, consumed_pending = apply_pending_session_defaults(paths, meta)
            meta = profile_meta(paths, str(meta["id"]))
            runtime_home, sqlite_home = materialize_runtime(
                paths,
                meta,
                index,
                args.sqlite_build_key,
            )
        if consumed_pending is not None:
            consumed_pending.unlink(missing_ok=True)
        emit(
            True,
            active=True,
            profile=redact_profile(paths, meta),
            runtime_home=str(runtime_home),
            sqlite_home=str(sqlite_home),
            session_defaults=pending_result,
        )


def cmd_profile_sync_selection(paths: Paths, args: argparse.Namespace) -> None:
    """Persist one live TUI model selection into its owning profile immediately."""
    if not PROFILE_GENERATION_RE.fullmatch(args.base_generation):
        raise EngineError("配置档代次无效", 2, reason="invalid-generation")
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        current = resolve_profile(paths, args.profile)
        expected_runtime = runtime_home_for_profile(paths, current)
        source_dir = Path(args.source_dir).expanduser().resolve()
        if source_dir != expected_runtime:
            raise EngineError(
                "运行目录与配置档不匹配",
                7,
                reason="runtime-mismatch",
                expected=str(expected_runtime),
                actual=str(source_dir),
            )

        directory = profile_dir(paths, str(current["id"]))
        current_generation = profile_generation(directory)
        if args.base_generation != current_generation:
            raise EngineError(
                "配置档已由其他会话更新",
                9,
                reason="stale-generation",
                current_generation=current_generation,
            )

        runtime_doc = read_toml(source_dir / "config.toml")
        model, effort = validate_profile_selection(
            paths,
            current,
            runtime_doc.get("model"),
            runtime_doc.get("model_reasoning_effort"),
            runtime_doc.get("model_provider"),
        )
        managed_path = directory / "managed.toml"
        managed = read_toml(managed_path)
        previous_model = str(managed.get("model") or "")
        previous_effort = (
            str(managed["model_reasoning_effort"])
            if "model_reasoning_effort" in managed
            else None
        )
        changed = previous_model != model or previous_effort != effort
        if changed:
            with transaction(paths, "profile-sync-selection"):
                managed["model"] = model
                if effort is None:
                    managed.pop("model_reasoning_effort", None)
                else:
                    managed["model_reasoning_effort"] = effort
                atomic_write_text(managed_path, tomlkit.dumps(managed), 0o600)
                updated_meta = dict(current)
                updated_meta["updated_at"] = utc_now()
                atomic_write_json(directory / "profile.json", updated_meta)
                index = load_index(paths, create=True)
                if index.get("active_profile_id") == current["id"]:
                    materialize_profile(paths, updated_meta, index)
                current = updated_meta

        pending_session_defaults_path(paths, str(current["id"])).unlink(missing_ok=True)
        generation = profile_generation(directory)
        emit(
            True,
            status="applied" if changed else "unchanged",
            model=model,
            reasoning_effort=effort,
            previous_model=previous_model,
            previous_reasoning_effort=previous_effort,
            generation=generation,
            profile=redact_profile(paths, current),
        )


def cmd_profile_sync_runtime(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        current = resolve_profile(paths, args.profile)
        expected_runtime = runtime_home_for_profile(paths, current)
        source_dir = Path(args.source_dir).expanduser().resolve()
        if source_dir != expected_runtime:
            raise EngineError(
                "运行目录与配置档不匹配",
                7,
                expected=str(expected_runtime),
                actual=str(source_dir),
            )
        with transaction(paths, "profile-sync-runtime"):
            runtime_doc = read_toml(source_dir / "config.toml")
            index = load_index(paths, create=True)
            directory = profile_dir(paths, str(current["id"]))
            current_common = load_common_config(paths, index)
            previous_common_path = directory / COMMON_BASE_FILE
            if not previous_common_path.is_file():
                previous_common_path = directory / "legacy-config.toml"
            previous_common = (
                read_toml(previous_common_path)
                if previous_common_path.is_file()
                else tomlkit.document()
            )
            write_runtime_local_overlay(
                directory,
                extract_runtime_local_overlay(
                    runtime_doc,
                    current_common,
                    previous_common,
                ),
            )
            # Runtime processes may be concurrent and stale. Automatic exit
            # sync never imports profile-owned model/provider/reasoning fields.
            # Official login credentials are the one runtime-owned exception.
            if current.get("mode") == "official":
                runtime_auth = source_dir / "auth.json"
                if runtime_auth.is_file():
                    safe_copy(runtime_auth, directory / "auth.json", 0o600)
                    safe_copy(runtime_auth, paths.auth, 0o600)
            write_profile_base_config(paths.config, directory / COMMON_BASE_FILE)
            if index.get("active_profile_id") == current["id"]:
                materialize_profile(paths, current, index)
        emit(True, profile=redact_profile(paths, current))


def validate_catalog(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or not isinstance(value.get("models"), list):
        raise EngineError("上游模型目录格式无效", 7)
    seen: set[str] = set()
    for model in value["models"]:
        if not isinstance(model, dict) or not isinstance(model.get("slug"), str):
            raise EngineError("上游模型条目格式无效", 7)
        slug = model["slug"]
        if slug in seen:
            raise EngineError("上游模型目录存在重复 slug", 7, slug=slug)
        seen.add(slug)
        for key in ("context_window", "max_context_window", "auto_compact_token_limit"):
            item = model.get(key)
            if item is not None and (not isinstance(item, int) or item <= 0):
                raise EngineError("上游模型上下文字段无效", 7, slug=slug, field=key)
        levels = model.get("supported_reasoning_levels")
        if not isinstance(levels, list):
            raise EngineError("上游模型推理等级格式无效", 7, slug=slug)
    return value


def bundled_catalog_path() -> Path:
    return SCRIPT_DIR.parent / "data" / "openai-models.json"


def verified_file_meta(data_path: Path, meta_path: Path) -> dict[str, Any]:
    try:
        meta = read_json(meta_path, {}) or {}
    except EngineError:
        return {}
    if not isinstance(meta, dict) or not data_path.is_file():
        return {}
    expected = meta.get("sha256")
    if not isinstance(expected, str) or expected.lower() != sha256_file(data_path).lower():
        return {}
    return meta


def fetch_official_catalog(paths: Paths, offline: bool = False) -> tuple[dict[str, Any], dict[str, Any]]:
    ensure_private_dir(paths.catalog_cache)
    cache = paths.catalog_cache / "openai-models.json"
    meta_path = paths.catalog_cache / "openai-models.meta.json"
    meta = verified_file_meta(cache, meta_path)
    url = os.environ.get("CODEX_CONFIG_OFFICIAL_CATALOG_URL", OFFICIAL_CATALOG_URL).strip()
    if url and not offline and os.environ.get("CODEX_CONFIG_CATALOG_OFFLINE") != "1":
        request = urllib.request.Request(url, headers={"User-Agent": "codex-for-tui-config/2"})
        if isinstance(meta.get("etag"), str):
            request.add_header("If-None-Match", meta["etag"])
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                data = response.read(2 * 1024 * 1024 + 1)
                if len(data) > 2 * 1024 * 1024:
                    raise EngineError("上游模型目录超过大小限制", 7)
                value = validate_catalog(json.loads(data.decode("utf-8")))
                new_meta = {
                    "source": "official",
                    "url": url,
                    "etag": response.headers.get("ETag"),
                    "fetched_at": utc_now(),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
                atomic_write_json(meta_path, new_meta)
                maybe_failpoint("after-official-catalog-meta-write")
                atomic_write_bytes(cache, data, 0o600)
                return value, new_meta
        except urllib.error.HTTPError as exc:
            if exc.code == 304 and cache.is_file():
                return validate_catalog(read_json(cache)), {**meta, "source": "cache-304"}
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, EngineError):
            pass
    if cache.is_file():
        actual_sha = sha256_file(cache)
        return validate_catalog(read_json(cache)), {
            **meta,
            "source": "last-known-good",
            "sha256": actual_sha,
            "metadata_verified": bool(meta),
        }
    mirror = bundled_catalog_path()
    if mirror.is_file():
        return validate_catalog(read_json(mirror)), {
            "source": "bundled-mirror",
            "path": str(mirror),
            "sha256": sha256_file(mirror),
        }
    raise EngineError("官方模型目录、缓存和发布镜像均不可用", 6)


def provider_model_ids(path: Path) -> list[str]:
    value = read_json(path)
    items: Any
    if isinstance(value, dict) and isinstance(value.get("data"), list):
        items = value["data"]
    elif isinstance(value, dict) and isinstance(value.get("models"), list):
        items = value["models"]
    elif isinstance(value, list):
        items = value
    else:
        raise EngineError("Provider 模型列表格式无效", 7)
    result: list[str] = []
    for item in items:
        slug = item.get("id") if isinstance(item, dict) else item
        if isinstance(slug, str) and slug.strip() and slug.strip() not in result:
            result.append(slug.strip())
    if not result:
        raise EngineError("Provider 没有返回可用模型", 7)
    return result


def fallback_instructions(official: dict[str, Any]) -> tuple[str, str]:
    models = official.get("models")
    if not isinstance(models, list):
        raise EngineError("官方模型目录缺少可用的基础指令", 7)
    by_slug = {
        item.get("slug"): item
        for item in models
        if isinstance(item, dict) and isinstance(item.get("slug"), str)
    }
    preferred = ("gpt-5.4", "gpt-5.2")
    candidates = [by_slug.get(slug) for slug in preferred]
    candidates.extend(item for item in models if isinstance(item, dict))
    for item in candidates:
        if not isinstance(item, dict):
            continue
        instructions = item.get("base_instructions")
        source_slug = item.get("slug")
        if (
            isinstance(instructions, str)
            and instructions.strip()
            and isinstance(source_slug, str)
        ):
            return source_slug, instructions
    raise EngineError("官方模型目录缺少可用的基础指令", 7)


def conservative_unknown_model(slug: str, base_instructions: str) -> dict[str, Any]:
    return {
        "prefer_websockets": False,
        "support_verbosity": False,
        "default_verbosity": None,
        "apply_patch_tool_type": None,
        "web_search_tool_type": "text",
        "input_modalities": ["text"],
        "supports_image_detail_original": False,
        "truncation_policy": {"mode": "bytes", "limit": 10000},
        "supports_parallel_tool_calls": False,
        "context_window": None,
        "max_context_window": None,
        "auto_compact_token_limit": None,
        "reasoning_summary_format": "none",
        "default_reasoning_summary": "none",
        "additional_speed_tiers": [],
        "service_tiers": [],
        "default_service_tier": None,
        "slug": slug,
        "display_name": slug,
        "description": f"{slug} (provider metadata unavailable)",
        "default_reasoning_level": None,
        "supported_reasoning_levels": [],
        "shell_type": "shell_command",
        "visibility": "list",
        "minimal_client_version": "0.0.0",
        "supported_in_api": True,
        "availability_nux": None,
        "available_in_plans": [],
        "upgrade": None,
        "priority": 0,
        "base_instructions": base_instructions,
        "model_messages": None,
        "supports_reasoning_summaries": False,
        "effective_context_window_percent": 95,
        "experimental_supported_tools": [],
        "supports_search_tool": False,
        "use_responses_lite": False,
        "comp_hash": None,
        "auto_review_model_override": None,
        "tool_mode": None,
        "multi_agent_version": None,
        "include_skills_usage_instructions": False,
    }


def apply_catalog_visibility_policy(model: dict[str, Any]) -> None:
    """Normalize catalog entries for this Android/musl runtime.

    - Hide codex-auto-* helper models so /model opens the full picker.
    - Clear code_mode_only: aarch64-unknown-linux-musl builds ship without the
      V8 code-mode runtime, so that tool_mode makes every tool call fail with
      "code mode is unavailable in this aarch64-unknown-linux-musl build".
    """
    slug = model.get("slug")
    if isinstance(slug, str) and slug.startswith("codex-auto-"):
        model["visibility"] = "hide"
    if model.get("tool_mode") == "code_mode_only":
        model["tool_mode"] = None


def write_catalog_with_visibility_policy(
    source: Path,
    destination: Path,
    *,
    fixed_compact_policy: bool = False,
) -> None:
    value = read_json(source)
    if not isinstance(value, dict) or not isinstance(value.get("models"), list):
        raise EngineError("模型目录格式无效", 7, path=str(source))
    for model in value["models"]:
        if isinstance(model, dict):
            apply_catalog_visibility_policy(model)
            if fixed_compact_policy:
                # Native Codex treats a changed comp_hash as an unconditional
                # auto-compact, even when usage is far below the user's fixed
                # threshold. Runtime-only neutralization makes the explicit
                # fixed limit authoritative; the profile catalog keeps the
                # upstream values so follow-model can restore them.
                model["comp_hash"] = None
                model["auto_compact_token_limit"] = None
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    atomic_write_text(destination, text, 0o600)


def build_catalog_value(
    paths: Paths,
    ids: list[str],
    mappings: dict[str, Any] | None = None,
    *,
    offline: bool = False,
    bundled_only: bool = False,
) -> tuple[dict[str, Any], dict[str, Any]]:
    if bundled_only:
        mirror = bundled_catalog_path()
        official = validate_catalog(read_json(mirror))
        source_meta = {
            "source": "bundled-mirror",
            "path": str(mirror),
            "sha256": sha256_file(mirror),
        }
    else:
        official, source_meta = fetch_official_catalog(paths, offline=offline)
    official_by_slug = {item["slug"]: item for item in official["models"]}
    fallback_instruction_slug, fallback_instruction_text = fallback_instructions(official)
    mappings = mappings or {}
    if not isinstance(mappings, dict):
        raise EngineError("模型映射文件必须是 JSON 对象", 2)
    models: list[dict[str, Any]] = []
    unknown: list[str] = []
    mapped: dict[str, str] = {}
    for slug in ids:
        source_slug = slug if slug in official_by_slug else mappings.get(slug)
        if isinstance(source_slug, str) and source_slug in official_by_slug:
            model = copy.deepcopy(official_by_slug[source_slug])
            model["slug"] = slug
            if slug != source_slug:
                model["display_name"] = slug
                model["description"] = f"{slug} (compatible with {source_slug})"
                mapped[slug] = source_slug
        else:
            model = conservative_unknown_model(slug, fallback_instruction_text)
            unknown.append(slug)
        apply_catalog_visibility_policy(model)
        models.append(model)
    result = {"models": models}
    output_text = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    meta = {
        "schema_version": 1,
        "generated_at": utc_now(),
        "provider_model_count": len(ids),
        "known_model_count": len(ids) - len(unknown),
        "unknown_models": unknown,
        "unknown_model_instruction_source": (
            fallback_instruction_slug if unknown else None
        ),
        "manual_mappings": mapped,
        "upstream": source_meta,
        "sha256": hashlib.sha256(output_text.encode("utf-8")).hexdigest(),
    }
    return result, meta


def write_catalog_pair(
    output: Path,
    value: dict[str, Any],
    meta: dict[str, Any],
) -> None:
    output_text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    actual_meta = {**meta, "sha256": hashlib.sha256(output_text.encode("utf-8")).hexdigest()}
    atomic_write_json(output.with_suffix(output.suffix + ".meta.json"), actual_meta)
    maybe_failpoint("after-catalog-meta-write")
    atomic_write_text(output, output_text, 0o600)


def cmd_catalog_build(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        ids = provider_model_ids(Path(args.provider_json))
        mappings = read_json(Path(args.mapping_file), {}) if args.mapping_file else {}
        result, meta = build_catalog_value(
            paths,
            ids,
            mappings,
            offline=args.offline,
        )
        output = Path(args.output)
        write_catalog_pair(output, result, meta)
    emit(True, output=str(output), **meta)


def cmd_catalog_status(paths: Paths, _args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        index = load_index(paths)
        active = index.get("active_profile_id")
        if not active:
            emit(True, active_profile_id=None, catalog=None)
            return
        directory = profile_dir(paths, str(active))
        catalog_file = directory / "model_catalog.json"
        meta_file = directory / "catalog.meta.json"
        try:
            meta = read_json(meta_file, {}) or {}
        except EngineError:
            meta = {}
        actual_sha = sha256_file(catalog_file) if catalog_file.is_file() else None
        expected_sha = meta.get("sha256") if isinstance(meta, dict) else None
        integrity = (
            "ok"
            if actual_sha is not None
            and isinstance(expected_sha, str)
            and actual_sha.lower() == expected_sha.lower()
            else "missing"
            if actual_sha is None or not isinstance(expected_sha, str)
            else "mismatch"
        )
        meta = {
            **meta,
            "integrity": integrity,
            "actual_sha256": actual_sha,
        }
    emit(True, active_profile_id=active, catalog=meta)


def model_capability_summary(model: dict[str, Any]) -> dict[str, Any]:
    context_window = model.get("context_window")
    max_context_window = model.get("max_context_window")
    resolved_context_window = (
        context_window if isinstance(context_window, int) else max_context_window
    )
    percent = model.get("effective_context_window_percent", 95)
    if not isinstance(percent, int) or percent <= 0:
        percent = 95
    effective_context_window = (
        (resolved_context_window * percent) // 100
        if isinstance(resolved_context_window, int)
        else None
    )
    configured_compact = model.get("auto_compact_token_limit")
    derived_compact = (
        (resolved_context_window * 9) // 10
        if isinstance(resolved_context_window, int)
        else None
    )
    if isinstance(configured_compact, int):
        auto_compact_token_limit = (
            min(configured_compact, derived_compact)
            if isinstance(derived_compact, int)
            else configured_compact
        )
        auto_compact_source = "catalog-explicit"
    else:
        auto_compact_token_limit = derived_compact
        auto_compact_source = (
            "derived-90-percent" if isinstance(derived_compact, int) else "unknown"
        )
    levels = model.get("supported_reasoning_levels") or []
    return {
        "slug": model.get("slug"),
        "display_name": model.get("display_name") or model.get("slug"),
        "reasoning_levels": [
            item.get("effort")
            for item in levels
            if isinstance(item, dict) and isinstance(item.get("effort"), str)
        ],
        "default_reasoning_level": model.get("default_reasoning_level"),
        "context_window": context_window,
        "max_context_window": max_context_window,
        "resolved_context_window": resolved_context_window,
        "effective_context_window_percent": percent,
        "effective_context_window": effective_context_window,
        "auto_compact_token_limit": auto_compact_token_limit,
        "auto_compact_source": auto_compact_source,
        "supports_parallel_tool_calls": bool(model.get("supports_parallel_tool_calls")),
        "input_modalities": model.get("input_modalities") or ["text"],
        "conservative_fallback": resolved_context_window is None,
    }


def cmd_catalog_inspect(_paths: Paths, args: argparse.Namespace) -> None:
    catalog = validate_catalog(read_json(Path(args.catalog_file)))
    summaries = [model_capability_summary(item) for item in catalog["models"]]
    if args.model:
        for summary in summaries:
            if summary["slug"] == args.model:
                emit(True, model=summary)
                return
        raise EngineError("模型不在目录中", 4, model=args.model)
    emit(True, models=summaries)


def cmd_compact_policy(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        index = load_index(paths, create=True)
        if args.mode == "show":
            emit(True, compact_policy=profile_compact_policy(None, index))
            return
        if args.mode == "follow-model":
            policy = {"mode": "follow-model"}
        else:
            if args.value is None or args.value <= 0:
                raise EngineError("固定压缩阈值必须是正整数", 2)
            policy = {"mode": "fixed", "value": args.value}
        with transaction(paths, "compact-policy"):
            # Global policy only — profiles do not own compact thresholds.
            index["compact_policy"] = policy
            atomic_write_json(paths.index, index)
            active = index.get("active_profile_id")
            if active:
                meta = profile_meta(paths, str(active))
                materialize_profile(paths, meta, index)
            else:
                doc = load_common_config(paths, index)
                apply_compact_policy(doc, index)
                atomic_write_text(paths.config, tomlkit.dumps(doc), 0o600)
                atomic_write_json(paths.index, index)
        emit(True, compact_policy=policy)


def legacy_profile_dirs(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    reserved = {"profiles", "drafts", "transactions", "legacy-v1"}
    return [
        item
        for item in sorted(root.iterdir())
        if item.is_dir() and item.name not in reserved and (item / "config.toml").is_file()
    ]


def _legacy_import_fingerprint(config_path: Path) -> tuple[str, str, str] | None:
    """Name-independent fingerprint: provider base_url + model + provider name."""
    if not config_path.is_file():
        return None
    try:
        doc = read_toml(config_path)
    except Exception:
        return None
    model = str(doc.get("model", "") or "").strip()
    provider_id = str(doc.get("model_provider", "") or "").strip()
    base_url = ""
    provider_name = ""
    providers = doc.get("model_providers") or {}
    if isinstance(providers, dict) and provider_id:
        provider = providers.get(provider_id) or {}
        if isinstance(provider, dict):
            base_url = str(provider.get("base_url", "") or "").strip()
            provider_name = str(provider.get("name", "") or "").strip()
    if not base_url and not model:
        return None
    return (base_url.rstrip("/").lower(), model.lower(), provider_name.lower())


def legacy_profile_already_imported(
    paths: Paths,
    valid_profiles: list[dict[str, Any]],
    legacy_dir: Path,
) -> bool:
    """Skip re-import when the station already exists under V2.

    Byte-equal legacy-config.toml alone is too strict: after the user edits a
    station (model/key/url), the next APK upgrade would create name-legacy,
    name-legacy-2, ... forever. Match by profile name or by base_url+model.
    """
    source = legacy_dir / "config.toml"
    if not source.is_file():
        return False
    preferred = legacy_dir.name.strip().lower()
    for item in valid_profiles:
        name = str(item.get("name", "")).strip().lower()
        if preferred and name == preferred:
            return True
        # Also treat name / name-legacy* as the same station family.
        if preferred and (
            name == preferred
            or name.startswith(f"{preferred}-legacy")
            or preferred.startswith(f"{name}-legacy")
        ):
            return True
    try:
        source_bytes = source.read_bytes()
    except OSError:
        source_bytes = b""
    source_fp = _legacy_import_fingerprint(source)
    for item in valid_profiles:
        directory = profile_dir(paths, str(item["id"]))
        for candidate_name in ("legacy-config.toml", "common-base.toml"):
            candidate = directory / candidate_name
            try:
                if source_bytes and candidate.is_file() and candidate.read_bytes() == source_bytes:
                    return True
            except OSError:
                pass
        # Fingerprint against managed provider + model.
        managed = directory / "managed.toml"
        try:
            if managed.is_file():
                mdoc = read_toml(managed)
                model = str(mdoc.get("model", "") or "").strip().lower()
                provider = mdoc.get("provider") or {}
                base_url = ""
                provider_name = ""
                if isinstance(provider, dict):
                    base_url = str(provider.get("base_url", "") or "").strip().rstrip("/").lower()
                    provider_name = str(provider.get("name", "") or "").strip().lower()
                if source_fp and (base_url, model, provider_name) == source_fp:
                    return True
                if source_fp and base_url and base_url == source_fp[0]:
                    # Same gateway already has a station; do not spawn -legacy.
                    return True
        except Exception:
            continue
        # Live redact_profile fields when available.
        item_url = str(item.get("base_url", "") or "").strip().rstrip("/").lower()
        item_model = str(item.get("model", "") or "").strip().lower()
        if source_fp and item_url and item_url == source_fp[0]:
            return True
        if source_fp and item_url and item_model and (item_url, item_model) == source_fp[:2]:
            return True
    return False


def backup_v1(paths: Paths) -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = paths.v1_backups / stamp
    ensure_private_dir(backup)
    legacy_backup = backup / "config-profiles"
    if paths.legacy_profiles_root.is_dir():
        ensure_private_dir(legacy_backup)
        current = paths.legacy_profiles_root / "current"
        if current.is_file():
            safe_copy(current, legacy_backup / "current", 0o600)
        for source_dir in legacy_profile_dirs(paths.legacy_profiles_root):
            destination = legacy_backup / source_dir.name
            ensure_private_dir(destination)
            for source, relative in (
                (source_dir / "config.toml", Path("config.toml")),
                (source_dir / "auth.json", Path("auth.json")),
                (source_dir / "model_catalog.json", Path("model_catalog.json")),
                (
                    source_dir / "install-state" / "official-login-mode",
                    Path("install-state") / "official-login-mode",
                ),
            ):
                if source.is_file():
                    safe_copy(source, destination / relative, 0o600)
    for source, name in (
        (paths.config, "config.toml"),
        (paths.auth, "auth.json"),
        (paths.catalog, "model_catalog.json"),
        (paths.official_marker, "official-login-mode"),
    ):
        if source.is_file():
            safe_copy(source, backup / name, 0o600)
    atomic_write_json(backup / "backup.json", {"created_at": utc_now(), "schema_version": 1})
    return backup


def restore_v1_backup(paths: Paths, backup: Path) -> None:
    if paths.profiles_root.exists():
        shutil.rmtree(paths.profiles_root)
    legacy_profiles = backup / "config-profiles"
    if legacy_profiles.is_dir():
        ensure_private_dir(paths.legacy_profiles_root)
        current = legacy_profiles / "current"
        if current.is_file():
            safe_copy(current, paths.legacy_profiles_root / "current", 0o600)
        for source_dir in legacy_profile_dirs(legacy_profiles):
            destination = paths.legacy_profiles_root / source_dir.name
            ensure_private_dir(destination)
            for source, relative in (
                (source_dir / "config.toml", Path("config.toml")),
                (source_dir / "auth.json", Path("auth.json")),
                (source_dir / "model_catalog.json", Path("model_catalog.json")),
                (
                    source_dir / "install-state" / "official-login-mode",
                    Path("install-state") / "official-login-mode",
                ),
            ):
                if source.is_file():
                    safe_copy(source, destination / relative, 0o600)
    for target, name in (
        (paths.config, "config.toml"),
        (paths.auth, "auth.json"),
        (paths.catalog, "model_catalog.json"),
        (paths.official_marker, "official-login-mode"),
    ):
        source = backup / name
        if source.is_file():
            safe_copy(source, target, 0o600)
        else:
            target.unlink(missing_ok=True)


def cmd_migrate_v1(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        if paths.index.is_file():
            index = load_index(paths)
            emit(True, migrated=False, reason="already-v2", index=index)
            return
        backup = backup_v1(paths)
        atomic_write_json(
            paths.journal,
            {
                "schema_version": 1,
                "kind": "v1-migration",
                "action": "migrate-v1",
                "phase": "prepared",
                "backup": str(backup),
                "started_at": utc_now(),
            },
        )
        maybe_failpoint("after-migration-journal")
        try:
            legacy_root = backup / "config-profiles"
            old_current = ""
            current_file = legacy_root / "current"
            if current_file.is_file():
                old_current = current_file.read_text(encoding="utf-8").strip()
            paths.ensure_v2_dirs()
            maybe_failpoint("after-v1-profile-reset")
            index = default_index()
            index["migration"] = {
                "v1_completed": True,
                "legacy_backup": str(backup),
                "completed_at": utc_now(),
            }
            if args.compact_policy == "fixed":
                index["compact_policy"] = {"mode": "fixed", "value": 220000}
            else:
                index["compact_policy"] = {"mode": "follow-model"}
                doc = read_toml(paths.config)
                if doc.get("model_auto_compact_token_limit") == 220000:
                    doc.pop("model_auto_compact_token_limit", None)
                    atomic_write_text(paths.config, tomlkit.dumps(doc))
            imported: list[dict[str, Any]] = []
            source_by_name: dict[str, dict[str, Any]] = {}
            for old_dir in legacy_profile_dirs(legacy_root):
                name = validate_profile_name(old_dir.name)
                ensure_unique_name(paths, name)
                meta = import_runtime_profile(
                    paths,
                    name=name,
                    source_dir=old_dir,
                    runtime_home=paths.legacy_profiles_root / name,
                )
                # Compact is global (index only); never mirror into station meta.
                meta.pop("compact_policy", None)
                atomic_write_json(
                    profile_dir(paths, str(meta["id"])) / "profile.json",
                    meta,
                )
                imported.append(meta)
                source_by_name[name] = meta
            if not imported and paths.config.is_file():
                meta = import_runtime_profile(paths, name="default", source_dir=paths.home)
                meta.pop("compact_policy", None)
                atomic_write_json(
                    profile_dir(paths, str(meta["id"])) / "profile.json",
                    meta,
                )
                imported.append(meta)
                source_by_name["default"] = meta
                old_current = "default"
            active = source_by_name.get(old_current)
            if active is None and imported:
                for item in imported:
                    legacy_cfg = profile_dir(paths, str(item["id"])) / "legacy-config.toml"
                    if legacy_cfg.is_file() and paths.config.is_file():
                        if legacy_cfg.read_bytes() == paths.config.read_bytes():
                            active = item
                            break
            atomic_write_json(paths.index, index)
            if active is not None:
                materialize_profile(paths, active, index)
            journal = read_json(paths.journal, {})
            journal["phase"] = "committed"
            journal["committed_at"] = utc_now()
            atomic_write_json(paths.journal, journal)
            paths.journal.unlink(missing_ok=True)
        except BaseException:
            restore_v1_backup(paths, backup)
            paths.journal.unlink(missing_ok=True)
            remove_snapshot(backup)
            raise
        emit(
            True,
            migrated=True,
            legacy_backup=str(backup),
            compact_policy=index["compact_policy"],
            imported_profiles=[redact_profile(paths, item) for item in imported],
            active_profile_id=index.get("active_profile_id"),
        )


def cmd_rollback_v1(paths: Paths, _args: argparse.Namespace) -> None:
    with engine_lock(paths):
        paths.ensure_v2_dirs()
        recover_transaction(paths)
        index = load_index(paths)
        backup_value = (index.get("migration") or {}).get("legacy_backup")
        if not isinstance(backup_value, str):
            raise EngineError("没有可恢复的 V1 迁移备份", 4)
        backup = Path(backup_value)
        if not backup.is_dir():
            raise EngineError("V1 迁移备份不存在", 4, backup=str(backup))
        with transaction(paths, "rollback-v1", retain_backup=True) as archived:
            restore_v1_backup(paths, backup)
            maybe_failpoint("after-v1-rollback-restore")
        emit(True, restored_backup=str(backup), archived_v2=str(archived))


def list_profiles_tolerant(paths: Paths) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    valid: list[dict[str, Any]] = []
    invalid: list[dict[str, str]] = []
    if not paths.profiles.is_dir():
        return valid, invalid
    for directory in sorted(paths.profiles.iterdir()):
        if not directory.is_dir():
            continue
        if not PROFILE_ID_RE.fullmatch(directory.name):
            invalid.append({"path": str(directory), "reason": "invalid-directory-name"})
            continue
        try:
            valid.append(profile_meta(paths, directory.name))
        except EngineError as exc:
            invalid.append({"path": str(directory), "reason": exc.message})
    return (
        sorted(valid, key=lambda item: (str(item.get("name", "")).lower(), item.get("id", ""))),
        invalid,
    )


def unique_profile_name(paths: Paths, preferred: str, suffix: str = "imported") -> str:
    base = preferred if PROFILE_NAME_RE.fullmatch(preferred) else "profile"
    valid, _invalid = list_profiles_tolerant(paths)
    names = {str(item.get("name", "")) for item in valid}
    if base not in names:
        return base
    candidate = f"{base}-{suffix}"
    if candidate not in names and PROFILE_NAME_RE.fullmatch(candidate):
        return candidate
    counter = 2
    while True:
        candidate = f"{base}-{suffix}-{counter}"
        if candidate not in names and PROFILE_NAME_RE.fullmatch(candidate):
            return candidate
        counter += 1


def archive_corrupt_file(source: Path, destination_dir: Path, label: str) -> str | None:
    if not source.exists():
        return None
    ensure_private_dir(destination_dir)
    destination = destination_dir / f"{label}-{dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')}"
    if source.is_file():
        safe_copy(source, destination, 0o600)
        source.unlink(missing_ok=True)
    else:
        os.replace(source, destination)
    return str(destination)


def snapshot_runtime_source(paths: Paths, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    ensure_private_dir(destination)
    for source, relative in (
        (paths.config, Path("config.toml")),
        (paths.auth, Path("auth.json")),
        (paths.catalog, Path("model_catalog.json")),
        (
            paths.official_marker,
            Path("install-state") / "official-login-mode",
        ),
    ):
        if source.is_file():
            safe_copy(source, destination / relative, 0o600)


def copy_regular_tree(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return
    ensure_private_dir(destination)
    for root, directories, files in os.walk(source):
        root_path = Path(root)
        relative = root_path.relative_to(source)
        target_root = destination / relative
        ensure_private_dir(target_root)
        directories[:] = [
            name
            for name in directories
            if not (root_path / name).is_symlink()
        ]
        for name in files:
            item = root_path / name
            target = target_root / name
            try:
                mode = item.lstat().st_mode
            except OSError:
                continue
            if not stat.S_ISREG(mode) or item.is_symlink() or target.exists():
                continue
            safe_copy(item, target, stat.S_IMODE(mode))


def _merge_tree_into(source_tree: Path, target_tree: Path) -> None:
    """Deep-merge files from source_tree into target_tree without overwriting.

    Used when a per-runtime private sessions/history tree must be absorbed into
    the shared control home before the private tree is replaced by a symlink.
    Existing target files win (same path keeps control copy).
    """
    if not source_tree.is_dir():
        return
    ensure_private_dir(target_tree)
    for root, directories, files in os.walk(source_tree, followlinks=False):
        root_path = Path(root)
        try:
            relative = root_path.relative_to(source_tree)
        except ValueError:
            continue
        target_root = target_tree / relative
        ensure_private_dir(target_root)
        # Do not walk into symlinked subtrees (avoid escaping runtime home).
        directories[:] = [
            name for name in directories if not (root_path / name).is_symlink()
        ]
        for name in directories:
            ensure_private_dir(target_root / name)
        for name in files:
            item = root_path / name
            target = target_root / name
            if item.is_symlink():
                continue
            try:
                mode = item.lstat().st_mode
            except OSError:
                continue
            if not stat.S_ISREG(mode):
                continue
            if target.exists() or target.is_symlink():
                continue
            try:
                safe_copy(item, target, stat.S_IMODE(mode))
            except (OSError, EngineError):
                continue


def _paths_resolve_equal(left: Path, right: Path) -> bool:
    try:
        return left.resolve(strict=False) == right.resolve(strict=False)
    except OSError:
        return False


def seed_runtime_state(source_home: Path, runtime_home: Path) -> list[str]:
    """Share conversation state across config profiles.

    Different profiles keep isolated config.toml / auth / sqlite under
    config-runtimes/, but sessions + history + shell_snapshots must resolve
    to the control CODEX_HOME so switching model_providers.custom (or any
    profile) still sees the same conversation list.

    Idempotent and repair-oriented:
    - wrong/broken symlinks are rewritten to control home
    - private real dirs are deep-merged into control then replaced by symlink
    - never leaves a runtime with a private or empty-wrong sessions tree
    """
    if _paths_resolve_equal(runtime_home, source_home):
        raise EngineError("配置运行目录未隔离", 7)
    linked: list[str] = []

    def _link_shared(name: str, is_dir: bool) -> None:
        source = source_home / name
        destination = runtime_home / name
        # Ensure control-home target exists so symlink is usable immediately.
        if is_dir:
            ensure_private_dir(source)
        else:
            if not source.exists():
                source.parent.mkdir(parents=True, exist_ok=True)
                source.touch(exist_ok=True)
                try:
                    source.chmod(0o600)
                except OSError:
                    pass
        if destination.is_symlink():
            if _paths_resolve_equal(destination, source):
                linked.append(name)
                return
            # Wrong or broken link (e.g. legacy empty profile path) → rewrite.
            try:
                destination.unlink()
            except OSError:
                return
        elif destination.exists():
            # Migrate any per-runtime private data into the shared control home
            # (deep merge — year/month subdirs often already exist on control),
            # then replace with a symlink.
            if is_dir and destination.is_dir() and not destination.is_symlink():
                try:
                    _merge_tree_into(destination, source)
                except OSError:
                    pass
                shutil.rmtree(destination, ignore_errors=True)
            elif destination.is_file() and source.is_file():
                # Prefer the larger history (more complete).
                try:
                    if destination.stat().st_size > source.stat().st_size:
                        safe_copy(destination, source, 0o600)
                except OSError:
                    pass
                destination.unlink(missing_ok=True)
            else:
                if destination.is_dir():
                    shutil.rmtree(destination, ignore_errors=True)
                else:
                    destination.unlink(missing_ok=True)
        try:
            destination.symlink_to(source, target_is_directory=is_dir)
            linked.append(name)
        except OSError:
            # Fallback: copy once if symlink not permitted.
            if is_dir:
                copy_regular_tree(source, destination)
            elif source.is_file() and not destination.exists():
                safe_copy(source, destination, 0o600)
            linked.append(name)

    _link_shared("history.jsonl", is_dir=False)
    for name in ("sessions", "archived_sessions", "shell_snapshots"):
        _link_shared(name, is_dir=True)
    return linked


def seed_root_runtime_state(paths: Paths, runtime_home: Path) -> list[str]:
    return seed_runtime_state(paths.home, runtime_home)


def seed_all_runtime_states(paths: Paths) -> dict[str, list[str]]:
    """Repair shared session links for every config-runtimes/* home.

    Launch/materialize already seeds the active runtime; this catches idle
    runtimes that still hold private dirs or wrong legacy symlinks so switching
    profile never shows an empty / partial /resume list.
    """
    result: dict[str, list[str]] = {}
    root = paths.home / "config-runtimes"
    if not root.is_dir():
        return result
    try:
        children = sorted(root.iterdir())
    except OSError:
        return result
    for child in children:
        if not child.is_dir() or child.is_symlink():
            continue
        # Skip nested garbage under a runtime (sqlite-builds etc. are not homes).
        if not (child / "config.toml").is_file() and not any(child.glob("sqlite-builds")):
            # Still seed if it looks like a runtime id directory.
            if not child.name.startswith("p-"):
                continue
        try:
            result[child.name] = seed_runtime_state(paths.home, child)
        except EngineError:
            continue
        except OSError:
            continue
    return result


def _read_runtime_model_provider(runtime_home: Path) -> str | None:
    """Return model_provider id from a runtime config.toml, if present."""
    config_path = runtime_home / "config.toml"
    if not config_path.is_file():
        return None
    try:
        doc = read_toml(config_path)
    except Exception:
        return None
    value = doc.get("model_provider")
    if isinstance(value, str):
        provider = value.strip()
        if provider:
            return provider
    return None


def _read_control_model_provider(paths: Paths) -> str | None:
    """Return model_provider from control config.toml when present."""
    if not paths.config.is_file():
        return None
    try:
        doc = read_toml(paths.config)
    except Exception:
        return None
    value = doc.get("model_provider")
    if isinstance(value, str):
        provider = value.strip()
        if provider:
            return provider
    return None


def _rewrite_rollout_session_meta_provider(path: Path, target: str) -> bool:
    """Rewrite session_meta.model_provider in one rollout jsonl. Returns True if changed.

    Codex startup backfill rebuilds SQLite threads from rollout session_meta. Only
    restamping SQLite is not durable: the next launch reloads the old provider
    from jsonl and empties /resume again. Codex++ provider-sync rewrites both.

    Performance: native rollouts put session_meta on the first jsonl line. Reading
    multi-hundred-MB bodies on every marker miss was the dominant cold-start cost
    (tens of seconds on phone storage). Only the first line is inspected; no-ops
    return without touching the rest. Same-length provider ids are patched in
    place; otherwise the rest is streamed (never slurp whole file into RAM).
    """
    if not target:
        return False
    try:
        with path.open("rb") as handle:
            first = handle.readline(16 * 1024 * 1024)
            if not first:
                return False
            rest_offset = handle.tell()
    except OSError:
        return False

    had_newline = first.endswith(b"\n")
    raw = first[:-1] if had_newline else first
    try:
        record = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        # Extremely rare non-leading session_meta: fall back to legacy full scan
        # only for small files so huge bodies never pay the old cost.
        try:
            size = path.stat().st_size
        except OSError:
            return False
        if size > 4 * 1024 * 1024:
            return False
        return _rewrite_rollout_session_meta_provider_full(path, target)

    if not isinstance(record, dict) or record.get("type") != "session_meta":
        try:
            size = path.stat().st_size
        except OSError:
            return False
        if size > 4 * 1024 * 1024:
            return False
        return _rewrite_rollout_session_meta_provider_full(path, target)

    payload = record.get("payload")
    if not isinstance(payload, dict):
        return False
    current = payload.get("model_provider")
    if current == target:
        return False
    payload["model_provider"] = target
    record["payload"] = payload
    new_raw = json.dumps(record, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    new_first = new_raw + (b"\n" if had_newline else b"")

    try:
        stat = path.stat()
    except OSError:
        stat = None

    # Managed provider ids are fixed-width (codex_tui_ + 12 hex). Same-length
    # patches avoid rewriting the multi-MB body entirely.
    if len(new_first) == len(first):
        try:
            with path.open("r+b") as handle:
                handle.seek(0)
                handle.write(new_first)
                handle.flush()
                os.fsync(handle.fileno())
            if stat is not None:
                try:
                    os.utime(path, (stat.st_atime, stat.st_mtime))
                except OSError:
                    pass
            try:
                path.chmod(0o600)
            except OSError:
                pass
            return True
        except OSError:
            # Fall through to streaming rewrite.
            pass

    ensure_private_dir(path.parent)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as out_handle, path.open("rb") as in_handle:
            out_handle.write(new_first)
            in_handle.seek(rest_offset)
            shutil.copyfileobj(in_handle, out_handle, length=1024 * 1024)
            out_handle.flush()
            os.fsync(out_handle.fileno())
        tmp.chmod(0o600)
        os.replace(tmp, path)
        fsync_dir(path.parent)
        if stat is not None:
            try:
                os.utime(path, (stat.st_atime, stat.st_mtime))
            except OSError:
                pass
    except Exception:
        tmp.unlink(missing_ok=True)
        return False
    return True


def _rewrite_rollout_session_meta_provider_full(path: Path, target: str) -> bool:
    """Legacy full-file rewrite for tiny atypical rollouts only."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    if not text:
        return False
    changed = False
    out_parts: list[str] = []
    for line in text.splitlines(keepends=True):
        raw = line[:-1] if line.endswith("\n") else line
        ending = "\n" if line.endswith("\n") else ""
        stripped = raw.strip()
        if not stripped:
            out_parts.append(line)
            continue
        try:
            record = json.loads(stripped)
        except json.JSONDecodeError:
            out_parts.append(line)
            continue
        if not isinstance(record, dict) or record.get("type") != "session_meta":
            out_parts.append(line)
            continue
        payload = record.get("payload")
        if not isinstance(payload, dict):
            out_parts.append(line)
            continue
        current = payload.get("model_provider")
        if current == target:
            out_parts.append(line)
            continue
        payload["model_provider"] = target
        record["payload"] = payload
        out_parts.append(
            json.dumps(record, ensure_ascii=False, separators=(",", ":")) + ending
        )
        changed = True
    if not changed:
        return False
    try:
        stat = path.stat()
    except OSError:
        stat = None
    try:
        atomic_write_text(path, "".join(out_parts), 0o600)
        if stat is not None:
            try:
                os.utime(path, (stat.st_atime, stat.st_mtime))
            except OSError:
                pass
    except Exception:
        return False
    return True


def rewrite_shared_session_meta_providers(
    paths: Paths,
    provider: str,
) -> dict[str, Any]:
    """Rewrite shared rollout session_meta to the active station provider."""
    summary: dict[str, Any] = {
        "provider": provider,
        "files_scanned": 0,
        "files_updated": 0,
        "roots": [],
    }
    if not provider:
        summary["skipped"] = True
        summary["reason"] = "no-model-provider"
        return summary
    roots: list[Path] = []
    for name in ("sessions", "archived_sessions"):
        root = paths.home / name
        # Follow symlink to control body; seed makes runtime sessions -> control.
        try:
            if root.exists():
                roots.append(root.resolve() if root.is_symlink() else root)
        except OSError:
            continue
    seen: set[str] = set()
    for root in roots:
        key = str(root)
        if key in seen or not root.is_dir():
            continue
        seen.add(key)
        summary["roots"].append(key)
        try:
            files = sorted(root.rglob("rollout-*.jsonl"))
        except OSError:
            continue
        for path in files:
            if not path.is_file() or path.is_symlink():
                continue
            summary["files_scanned"] += 1
            if _rewrite_rollout_session_meta_provider(path, provider):
                summary["files_updated"] += 1
    return summary


def restamp_runtime_thread_providers(
    runtime_home: Path,
    provider: str | None = None,
) -> dict[str, Any]:
    """Stamp SQLite threads.model_provider to this runtime's provider.

    Codex TUI /resume filters by the active model_provider_id. Shared sessions
    are inventory-unified across relays, but historical rows keep the provider
    id from the station that first created them. Without restamping, switching
    to another relay shows an empty picker even though the sessions tree is
    shared.

    Also set has_user_event=1 when the column exists and is 0: Codex++ does the
    same visibility repair; preview-empty filtering is separate and already
    handled by native backfill for normal user threads.
    """
    import sqlite3

    target = provider or _read_runtime_model_provider(runtime_home)
    summary: dict[str, Any] = {
        "runtime_home": str(runtime_home),
        "provider": target,
        "databases": 0,
        "updated_rows": 0,
        "user_event_rows": 0,
        "skipped": False,
    }
    if not target:
        summary["skipped"] = True
        summary["reason"] = "no-model-provider"
        return summary
    builds = runtime_home / "sqlite-builds"
    if not builds.is_dir():
        summary["skipped"] = True
        summary["reason"] = "no-sqlite-builds"
        return summary
    for db in sorted(builds.glob("*/state_5.sqlite")):
        if not db.is_file() or db.is_symlink():
            continue
        try:
            con = sqlite3.connect(str(db), timeout=10)
            try:
                cols = {
                    str(row[1])
                    for row in con.execute("PRAGMA table_info(threads)")
                }
                if "model_provider" not in cols:
                    continue
                before = int(
                    con.execute(
                        "SELECT COUNT(*) FROM threads "
                        "WHERE model_provider IS NULL OR model_provider != ?",
                        (target,),
                    ).fetchone()[0]
                )
                if before:
                    con.execute(
                        "UPDATE threads SET model_provider = ? "
                        "WHERE model_provider IS NULL OR model_provider != ?",
                        (target, target),
                    )
                user_event_rows = 0
                if "has_user_event" in cols:
                    user_event_rows = int(
                        con.execute(
                            "SELECT COUNT(*) FROM threads "
                            "WHERE COALESCE(has_user_event, 0) = 0"
                        ).fetchone()[0]
                    )
                    if user_event_rows:
                        con.execute(
                            "UPDATE threads SET has_user_event = 1 "
                            "WHERE COALESCE(has_user_event, 0) = 0"
                        )
                if before or user_event_rows:
                    con.commit()
                summary["databases"] += 1
                summary["updated_rows"] += before
                summary["user_event_rows"] += user_event_rows
            finally:
                con.close()
        except sqlite3.Error:
            continue
        except OSError:
            continue
    return summary


def restamp_all_runtime_thread_providers(paths: Paths) -> dict[str, Any]:
    """Restamp provider ids for every config-runtimes/* SQLite index."""
    root = paths.home / "config-runtimes"
    result: dict[str, Any] = {}
    if not root.is_dir():
        return result
    try:
        children = sorted(root.iterdir())
    except OSError:
        return result
    for child in children:
        if not child.is_dir() or child.is_symlink():
            continue
        if not child.name.startswith("p-"):
            continue
        result[child.name] = restamp_runtime_thread_providers(child)
    return result


def restamp_all_runtime_thread_providers_to(
    paths: Paths,
    provider: str,
) -> dict[str, Any]:
    """Restamp every config-runtimes/* SQLite index to one provider id."""
    root = paths.home / "config-runtimes"
    result: dict[str, Any] = {}
    if not root.is_dir():
        return result
    try:
        children = sorted(root.iterdir())
    except OSError:
        return result
    for child in children:
        if not child.is_dir() or child.is_symlink():
            continue
        if not child.name.startswith("p-"):
            continue
        result[child.name] = restamp_runtime_thread_providers(child, provider)
    return result


def _provider_sync_marker_path(paths: Paths) -> Path:
    return paths.home / "install-state" / "provider-sync-v1.json"


def _provider_sync_marker_matches(paths: Paths, provider: str) -> bool:
    marker = _provider_sync_marker_path(paths)
    if not marker.is_file() or not provider:
        return False
    try:
        data = read_json(marker, {})
    except Exception:
        return False
    if not isinstance(data, dict):
        return False
    if str(data.get("provider", "")) != provider:
        return False
    # Marker is only trusted when session inventory mtime has not advanced.
    try:
        sessions = paths.home / "sessions"
        newest = 0.0
        if sessions.is_dir():
            for path in sessions.rglob("rollout-*.jsonl"):
                try:
                    newest = max(newest, path.stat().st_mtime)
                except OSError:
                    continue
        if float(data.get("sessions_mtime", -1)) + 0.0001 < newest:
            return False
    except OSError:
        return False
    return True


def _write_provider_sync_marker(paths: Paths, provider: str) -> None:
    newest = 0.0
    try:
        sessions = paths.home / "sessions"
        if sessions.is_dir():
            for path in sessions.rglob("rollout-*.jsonl"):
                try:
                    newest = max(newest, path.stat().st_mtime)
                except OSError:
                    continue
    except OSError:
        newest = 0.0
    ensure_private_dir(paths.home / "install-state")
    atomic_write_json(
        _provider_sync_marker_path(paths),
        {
            "provider": provider,
            "sessions_mtime": newest,
            "updated_at": utc_now(),
        },
    )


def sync_provider_visibility(
    paths: Paths,
    provider: str | None = None,
    runtime_home: Path | None = None,
    *,
    fast: bool = False,
) -> dict[str, Any]:
    """Codex++-style provider sync for resume visibility.

    1) Rewrite shared rollout session_meta.model_provider to the active provider
       so startup backfill cannot reintroduce old ids.
    2) Restamp every runtime SQLite index to the same active provider so any
       station's local DB lists the full shared inventory without --all.

    When fast=True and a marker already matches the target provider, only the
    launching runtime SQLite is restamped (cheap path for warm launches).
    """
    target = provider
    if not target and runtime_home is not None:
        target = _read_runtime_model_provider(runtime_home)
    if not target:
        target = _read_control_model_provider(paths)
    summary: dict[str, Any] = {
        "provider": target,
        "session_meta": {},
        "provider_restamped": {},
        "fast": bool(fast),
    }
    if not target:
        summary["skipped"] = True
        summary["reason"] = "no-model-provider"
        return summary
    if fast and _provider_sync_marker_matches(paths, target):
        restamped: dict[str, Any] = {}
        if runtime_home is not None:
            restamped[runtime_home.name] = restamp_runtime_thread_providers(
                runtime_home, target
            )
        summary["session_meta"] = {
            "skipped": True,
            "reason": "marker-match",
            "provider": target,
        }
        summary["provider_restamped"] = restamped
        summary["skipped_full_sync"] = True
        return summary
    summary["session_meta"] = rewrite_shared_session_meta_providers(paths, target)
    # Force all runtime DBs to the active station provider (Codex++ model).
    restamped = restamp_all_runtime_thread_providers_to(paths, target)
    if runtime_home is not None:
        restamped[runtime_home.name] = restamp_runtime_thread_providers(
            runtime_home, target
        )
    summary["provider_restamped"] = restamped
    try:
        _write_provider_sync_marker(paths, target)
    except Exception:
        pass
    return summary


def cmd_seed_shared_sessions(paths: Paths, _args: argparse.Namespace) -> None:
    """CLI entry: repair shared sessions/history links for all runtimes."""
    linked = seed_all_runtime_states(paths)
    # Seed path is pre-launch repair; use fast marker when already synced.
    synced = sync_provider_visibility(paths, fast=True)
    emit(
        True,
        repaired=sorted(linked.keys()),
        linked=linked,
        provider_sync=synced,
        provider_restamped=synced.get("provider_restamped", {}),
    )


def cmd_restamp_thread_providers(paths: Paths, _args: argparse.Namespace) -> None:
    """CLI entry: Codex++-style provider sync (session_meta + SQLite)."""
    # Explicit CLI always does a full dual-write (no fast skip).
    synced = sync_provider_visibility(paths, fast=False)
    emit(True, provider_sync=synced, provider_restamped=synced.get("provider_restamped", {}))


def catalog_model_ids(path: Path) -> list[str]:
    if not path.is_file():
        return []
    try:
        value = read_json(path)
    except EngineError:
        return []
    if not isinstance(value, dict) or not isinstance(value.get("models"), list):
        return []
    result: list[str] = []
    for item in value["models"]:
        slug = item.get("slug") if isinstance(item, dict) else None
        if isinstance(slug, str) and slug and slug not in result:
            result.append(slug)
    return result


def catalog_manual_mappings(directory: Path) -> dict[str, str]:
    try:
        meta = read_json(directory / "catalog.meta.json", {}) or {}
    except EngineError:
        return {}
    mappings = meta.get("manual_mappings") if isinstance(meta, dict) else None
    if not isinstance(mappings, dict):
        return {}
    return {
        str(key): str(value)
        for key, value in mappings.items()
        if isinstance(key, str) and isinstance(value, str)
    }


def catalog_by_slug(value: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        str(item["slug"]): item
        for item in value.get("models", [])
        if isinstance(item, dict) and isinstance(item.get("slug"), str)
    }


def normalize_profile_reasoning(
    paths: Paths,
    meta: dict[str, Any],
    catalog: dict[str, Any],
) -> dict[str, Any] | None:
    directory = profile_dir(paths, str(meta["id"]))
    managed_path = directory / "managed.toml"
    managed = read_toml(managed_path)
    model_slug = str(managed.get("model", ""))
    current = (
        str(managed["model_reasoning_effort"])
        if "model_reasoning_effort" in managed
        else None
    )
    if not current or not model_slug:
        return None
    model = catalog_by_slug(catalog).get(model_slug)
    levels = (
        [
            str(item.get("effort"))
            for item in model.get("supported_reasoning_levels", [])
            if isinstance(item, dict) and isinstance(item.get("effort"), str)
        ]
        if isinstance(model, dict)
        else []
    )
    if current in levels:
        return None
    fallback = model.get("default_reasoning_level") if isinstance(model, dict) else None
    if not isinstance(fallback, str) or fallback not in levels:
        fallback = None
    if fallback:
        managed["model_reasoning_effort"] = fallback
    else:
        managed.pop("model_reasoning_effort", None)
    atomic_write_text(managed_path, tomlkit.dumps(managed), 0o600)
    return {
        "profile_id": meta["id"],
        "profile_name": meta["name"],
        "model": model_slug,
        "from": current,
        "to": fallback,
        "supported": levels,
    }


def rebuild_profile_catalog(
    paths: Paths,
    meta: dict[str, Any],
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    directory = profile_dir(paths, str(meta["id"]))
    if meta.get("mode") == "official":
        catalog = validate_catalog(read_json(bundled_catalog_path()))
        return None, normalize_profile_reasoning(paths, meta, catalog)
    summary = managed_summary(directory)
    ids = catalog_model_ids(directory / "model_catalog.json")
    selected_model = str(summary.get("model") or "")
    if selected_model and selected_model not in ids:
        ids.insert(0, selected_model)
    if not ids:
        raise EngineError(
            "第三方配置缺少可重建的模型 ID",
            7,
            profile_id=meta["id"],
        )
    catalog, catalog_meta = build_catalog_value(
        paths,
        ids,
        catalog_manual_mappings(directory),
        offline=True,
        bundled_only=True,
    )
    output_text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    catalog_meta = {
        **catalog_meta,
        "sha256": hashlib.sha256(output_text.encode("utf-8")).hexdigest(),
        "rebuilt_for_apk_upgrade": True,
    }
    atomic_write_text(directory / "model_catalog.json", output_text, 0o600)
    atomic_write_json(directory / "catalog.meta.json", catalog_meta, 0o600)
    fallback = normalize_profile_reasoning(paths, meta, catalog)
    return catalog_meta, fallback


def cmd_apk_upgrade(paths: Paths, args: argparse.Namespace) -> None:
    release = validate_profile_name(args.release)
    release_state = paths.home / "install-state" / "apk-upgrades" / release
    corrupt_root = release_state / "corrupt"
    root_source = release_state / "root-source"
    recovered_transaction = False
    archived_corruption: list[str] = []
    trust_inherited = False
    with engine_lock(paths):
        if paths.journal.is_file():
            try:
                recovered_transaction = recover_transaction(paths)
            except EngineError:
                archived = archive_corrupt_file(
                    paths.journal,
                    corrupt_root,
                    "config-v2-transaction.json",
                )
                if archived:
                    archived_corruption.append(archived)
        snapshot_runtime_source(paths, root_source)
        root_config = root_source / "config.toml"
        if root_config.is_file():
            root_doc = read_toml(root_config)
            trust_inherited = inherit_workspace_trust(root_doc)
            if trust_inherited:
                atomic_write_text(root_config, tomlkit.dumps(root_doc), 0o600)
        with transaction(paths, f"apk-upgrade-{release}", retain_backup=True) as backup:
            paths.ensure_v2_dirs()
            if trust_inherited and paths.config.is_file():
                control_doc = read_toml(paths.config)
                if inherit_workspace_trust(control_doc):
                    atomic_write_text(paths.config, tomlkit.dumps(control_doc), 0o600)
            valid_index = False
            try:
                index = load_index(paths) if paths.index.is_file() else default_index()
                valid_index = paths.index.is_file()
            except EngineError:
                archived = archive_corrupt_file(paths.index, corrupt_root, "index.json")
                if archived:
                    archived_corruption.append(archived)
                index = default_index()

            valid_profiles, invalid_profiles = list_profiles_tolerant(paths)
            quarantined_profiles: list[dict[str, str]] = []
            for item in invalid_profiles:
                source = Path(item["path"])
                archived = archive_corrupt_file(
                    source,
                    corrupt_root / "profiles",
                    source.name,
                )
                quarantined_profiles.append(
                    {**item, "archive": archived or ""}
                )
            valid_profiles, _ = list_profiles_tolerant(paths)

            # Strip legacy per-station compact_policy copies; index is the sole source.
            for item in valid_profiles:
                if "compact_policy" in item:
                    item.pop("compact_policy", None)
                    atomic_write_json(
                        profile_dir(paths, str(item["id"])) / "profile.json",
                        item,
                    )

            imported_legacy: list[dict[str, Any]] = []
            legacy_current = ""
            current_file = paths.legacy_profiles_root / "current"
            if current_file.is_file():
                legacy_current = current_file.read_text(encoding="utf-8").strip()
            for legacy_dir in legacy_profile_dirs(paths.legacy_profiles_root):
                if legacy_profile_already_imported(paths, valid_profiles, legacy_dir):
                    continue
                preferred = validate_profile_name(legacy_dir.name)
                name = unique_profile_name(paths, preferred, "legacy")
                imported = import_runtime_profile(
                    paths,
                    name=name,
                    source_dir=legacy_dir,
                )
                # Always share control-home conversation state. Never point the
                # new runtime sessions tree at the legacy profile directory
                # (that path is often empty and breaks /resume to 0 rows).
                # Do not deep-merge legacy sessions here: workspace migration
                # imports them transactionally; merging early breaks late
                # upgrade rollback isolation.
                seed_runtime_state(
                    paths.home,
                    runtime_home_for_profile(paths, imported),
                )
                imported_legacy.append(imported)
                valid_profiles.append(imported)

            root_has_config = (root_source / "config.toml").is_file() or (
                root_source / "install-state" / "official-login-mode"
            ).is_file()
            active_meta: dict[str, Any] | None = None
            if root_has_config:
                active_ref = index.get("active_profile_id") if valid_index else None
                existing = None
                if isinstance(active_ref, str):
                    existing = next(
                        (item for item in valid_profiles if item.get("id") == active_ref),
                        None,
                    )
                if existing is not None:
                    root_existing = dict(existing)
                    root_existing["compact_policy"] = compact_policy_from_config(
                        root_source / "config.toml"
                    )
                    active_meta = import_runtime_profile(
                        paths,
                        name=str(existing["name"]),
                        source_dir=root_source,
                        profile_id=str(existing["id"]),
                        existing_meta=root_existing,
                        runtime_home=runtime_home_for_profile(paths, existing),
                    )
                else:
                    root_name = unique_profile_name(paths, "root", "apk")
                    active_meta = import_runtime_profile(
                        paths,
                        name=root_name,
                        source_dir=root_source,
                    )
            elif imported_legacy:
                active_meta = next(
                    (
                        item
                        for item in imported_legacy
                        if item.get("name") == legacy_current
                    ),
                    imported_legacy[0],
                )
            elif valid_profiles:
                active_ref = index.get("active_profile_id")
                active_meta = next(
                    (
                        item
                        for item in valid_profiles
                        if item.get("id") == active_ref
                    ),
                    valid_profiles[0],
                )

            catalog_reports: list[dict[str, Any]] = []
            effort_fallbacks: list[dict[str, Any]] = []
            valid_profiles, _ = list_profiles_tolerant(paths)
            for item in valid_profiles:
                catalog_meta, fallback = rebuild_profile_catalog(paths, item)
                if catalog_meta is not None:
                    catalog_reports.append(
                        {
                            "profile_id": item["id"],
                            "profile_name": item["name"],
                            "known_model_count": catalog_meta["known_model_count"],
                            "unknown_models": catalog_meta["unknown_models"],
                            "sha256": catalog_meta["sha256"],
                        }
                    )
                if fallback is not None:
                    effort_fallbacks.append(fallback)

            copied_runtime_state: list[str] = []
            if active_meta is not None:
                active_meta = profile_meta(paths, str(active_meta["id"]))
                index["compact_policy"] = profile_compact_policy(active_meta, index)
                materialize_profile(paths, active_meta, index)
                copied_runtime_state = seed_root_runtime_state(
                    paths,
                    runtime_home_for_profile(paths, active_meta),
                )
            else:
                index["active_profile_id"] = None
                atomic_write_json(paths.index, index)

            upgrades = index.setdefault("apk_upgrades", {})
            upgrades[release] = {
                "completed_at": utc_now(),
                "root_profile_id": active_meta.get("id") if active_meta else None,
                "root_priority": True,
                "catalog_source": "bundled-rust-v0.144.1",
            }
            index["migration"] = {
                **(index.get("migration") or {}),
                "v1_completed": True,
                "apk_release": release,
            }
            atomic_write_json(paths.index, index)
            maybe_failpoint("after-apk-upgrade-index-write")

        shutil.rmtree(root_source, ignore_errors=True)
    emit(
        True,
        release=release,
        backup=str(backup),
        recovered_transaction=recovered_transaction,
        archived_corruption=archived_corruption,
        quarantined_profiles=quarantined_profiles,
        imported_legacy_profiles=[
            redact_profile(paths, item) for item in imported_legacy
        ],
        active_profile=(
            redact_profile(paths, profile_meta(paths, str(active_meta["id"])))
            if active_meta is not None
            else None
        ),
        copied_runtime_state=copied_runtime_state,
        catalog_reports=catalog_reports,
        effort_fallbacks=effort_fallbacks,
        workspace_trust_inherited=trust_inherited,
    )


def validate_upgrade_backup(paths: Paths, backup_value: str) -> Path:
    backup = Path(backup_value).expanduser().resolve()
    root = paths.backups.resolve()
    try:
        backup.relative_to(root)
    except ValueError as exc:
        raise EngineError("升级恢复点不在受管目录内", 2, backup=str(backup)) from exc
    if not backup.is_dir() or not (backup / "snapshot.json").is_file():
        raise EngineError("升级恢复点不存在或已损坏", 4, backup=str(backup))
    return backup


def cmd_apk_rollback(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        backup = validate_upgrade_backup(paths, args.backup)
        with transaction(paths, "apk-upgrade-rollback", retain_backup=True) as archived:
            restore_snapshot(paths, backup)
    emit(True, restored_backup=str(backup), archived_current=str(archived))


def fetch_provider_models_for_profile(
    paths: Paths,
    meta: dict[str, Any],
    timeout: int,
) -> list[str]:
    directory = profile_dir(paths, str(meta["id"]))
    summary = managed_summary(directory)
    base_url = normalize_base_url(str(summary.get("base_url") or ""))
    auth = read_json(directory / "auth.json", {}) or {}
    key = auth.get("OPENAI_API_KEY") if isinstance(auth, dict) else None
    if not isinstance(key, str) or not key:
        raise EngineError("当前第三方配置缺少 API Key，跳过联网刷新", 4)
    request = urllib.request.Request(
        f"{base_url}/models",
        headers={
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "User-Agent": "codex-for-tui-apk-upgrade/2.4.3",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read(2 * 1024 * 1024 + 1)
    except (urllib.error.URLError, TimeoutError) as exc:
        raise EngineError("第三方模型目录刷新失败", 6) from exc
    if len(data) > 2 * 1024 * 1024:
        raise EngineError("第三方模型目录超过大小限制", 7)
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise EngineError("第三方模型目录不是有效 JSON", 7) from exc
    temporary = paths.home / "install-state" / "apk-refresh-provider.json"
    atomic_write_json(temporary, value)
    try:
        return provider_model_ids(temporary)
    finally:
        temporary.unlink(missing_ok=True)


def cmd_apk_refresh_active(paths: Paths, args: argparse.Namespace) -> None:
    with engine_lock(paths):
        recover_transaction(paths)
        index = load_index(paths)
        active = index.get("active_profile_id")
        if not isinstance(active, str) or not active:
            emit(True, refreshed=False, reason="no-active-profile")
            return
        meta = profile_meta(paths, active)
        if meta.get("mode") != "third_party":
            emit(True, refreshed=False, reason="official-profile")
            return
        ids = fetch_provider_models_for_profile(paths, meta, args.timeout)
        directory = profile_dir(paths, active)
        catalog, catalog_meta = build_catalog_value(
            paths,
            ids,
            catalog_manual_mappings(directory),
            offline=True,
            bundled_only=True,
        )
        with transaction(paths, "apk-refresh-active"):
            output_text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            catalog_meta = {
                **catalog_meta,
                "sha256": hashlib.sha256(output_text.encode("utf-8")).hexdigest(),
                "provider_refreshed_at": utc_now(),
            }
            atomic_write_text(directory / "model_catalog.json", output_text, 0o600)
            atomic_write_json(directory / "catalog.meta.json", catalog_meta, 0o600)
            fallback = normalize_profile_reasoning(paths, meta, catalog)
            materialize_profile(paths, profile_meta(paths, active), index)
    emit(
        True,
        refreshed=True,
        profile_id=active,
        provider_model_count=len(ids),
        catalog_sha256=catalog_meta["sha256"],
        effort_fallback=fallback,
    )


def cmd_status(paths: Paths, _args: argparse.Namespace) -> None:
    recovered = False
    runtime_dirty = False
    runtime_dirty_reasons: list[str] = []
    with engine_lock(paths):
        if paths.journal.is_file():
            recovered = recover_transaction(paths)
        index = load_index(paths) if paths.index.is_file() else None
        if index and index.get("active_profile_id"):
            active = profile_meta(paths, str(index["active_profile_id"]))
            clean, runtime_dirty_reasons = runtime_matches_profile(paths, active)
            runtime_dirty = not clean
    emit(
        True,
        schema_version=index.get("schema_version") if index else 1,
        active_profile_id=index.get("active_profile_id") if index else None,
        compact_policy=index.get("compact_policy") if index else None,
        profile_count=(
            len(list_profiles(paths))
            if index
            else len(legacy_profile_dirs(paths.legacy_profiles_root))
        ),
        recovered_transaction=recovered,
        runtime_dirty=runtime_dirty,
        runtime_dirty_reasons=runtime_dirty_reasons,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="codex-config-engine")
    parser.add_argument("--codex-home", default=os.environ.get("CODEX_HOME"))
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status").set_defaults(handler=cmd_status)

    profile = sub.add_parser("profile")
    profile_sub = profile.add_subparsers(dest="profile_command", required=True)
    profile_sub.add_parser("list").set_defaults(handler=cmd_profile_list)
    show = profile_sub.add_parser("show")
    show.add_argument("profile")
    show.set_defaults(handler=cmd_profile_show)

    create = profile_sub.add_parser("create")
    create.add_argument("--name", required=True)
    create.add_argument("--mode", choices=("third_party", "official"), default="third_party")
    create.add_argument("--provider-name", default="OpenAI")
    create.add_argument("--base-url")
    create.add_argument("--model")
    create.add_argument("--reasoning-effort")
    create.add_argument("--compatibility-model")
    create.add_argument("--auth-file")
    create.add_argument("--catalog-file")
    create.add_argument("--activate", action="store_true")
    create.set_defaults(handler=cmd_profile_create)

    update = profile_sub.add_parser("update")
    update.add_argument("profile")
    update.add_argument("--name")
    update.add_argument("--mode", choices=("third_party", "official"))
    update.add_argument("--provider-name")
    update.add_argument("--base-url")
    update.add_argument("--model")
    update.add_argument("--reasoning-effort")
    update.add_argument("--compatibility-model")
    update.add_argument("--auth-file")
    update.add_argument("--catalog-file")
    update.set_defaults(handler=cmd_profile_update)

    rename = profile_sub.add_parser("rename")
    rename.add_argument("profile")
    rename.add_argument("new_name")
    rename.set_defaults(handler=cmd_profile_rename)

    activate = profile_sub.add_parser("activate")
    activate.add_argument("profile")
    activate.set_defaults(handler=cmd_profile_activate)

    delete = profile_sub.add_parser("delete")
    delete.add_argument("profile")
    delete.add_argument("--allow-active", action="store_true")
    delete.set_defaults(handler=cmd_profile_delete)

    import_cmd = profile_sub.add_parser("import-current")
    import_cmd.add_argument("--name", required=True)
    import_cmd.add_argument("--activate", action="store_true")
    import_cmd.set_defaults(handler=cmd_profile_import)
    sync_current = profile_sub.add_parser("sync-current")
    sync_current.add_argument("profile")
    sync_current.set_defaults(handler=cmd_profile_sync_current)
    launch = profile_sub.add_parser("launch")
    launch.add_argument("profile", nargs="?")
    launch.add_argument("--sqlite-build-key", required=True)
    launch.set_defaults(handler=cmd_profile_launch)
    sync_selection = profile_sub.add_parser("sync-selection")
    sync_selection.add_argument("profile")
    sync_selection.add_argument("--source-dir", required=True)
    sync_selection.add_argument("--base-generation", required=True)
    sync_selection.set_defaults(handler=cmd_profile_sync_selection)
    sync_runtime = profile_sub.add_parser("sync-runtime")
    sync_runtime.add_argument("profile")
    sync_runtime.add_argument("--source-dir", required=True)
    sync_runtime.set_defaults(handler=cmd_profile_sync_runtime)

    catalog = sub.add_parser("catalog")
    catalog_sub = catalog.add_subparsers(dest="catalog_command", required=True)
    build = catalog_sub.add_parser("build")
    build.add_argument("--provider-json", required=True)
    build.add_argument("--output", required=True)
    build.add_argument("--mapping-file")
    build.add_argument("--offline", action="store_true")
    build.set_defaults(handler=cmd_catalog_build)
    catalog_sub.add_parser("status").set_defaults(handler=cmd_catalog_status)
    inspect = catalog_sub.add_parser("inspect")
    inspect.add_argument("--catalog-file", required=True)
    inspect.add_argument("--model")
    inspect.set_defaults(handler=cmd_catalog_inspect)

    compact = sub.add_parser("compact-policy")
    compact.add_argument("mode", choices=("show", "follow-model", "fixed"))
    compact.add_argument("value", type=int, nargs="?")
    compact.set_defaults(handler=cmd_compact_policy)

    migrate = sub.add_parser("migrate-v1")
    migrate.add_argument("--compact-policy", choices=("follow-model", "fixed"), required=True)
    migrate.set_defaults(handler=cmd_migrate_v1)
    sub.add_parser("rollback-v1").set_defaults(handler=cmd_rollback_v1)
    apk_upgrade = sub.add_parser("apk-upgrade")
    apk_upgrade.add_argument("--release", required=True)
    apk_upgrade.set_defaults(handler=cmd_apk_upgrade)
    apk_rollback = sub.add_parser("apk-rollback")
    apk_rollback.add_argument("--backup", required=True)
    apk_rollback.set_defaults(handler=cmd_apk_rollback)
    apk_refresh = sub.add_parser("apk-refresh-active")
    apk_refresh.add_argument("--timeout", type=int, default=8)
    apk_refresh.set_defaults(handler=cmd_apk_refresh_active)
    sub.add_parser("seed-shared-sessions").set_defaults(
        handler=cmd_seed_shared_sessions
    )
    sub.add_parser("restamp-thread-providers").set_defaults(
        handler=cmd_restamp_thread_providers
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    home_value = args.codex_home or str(Path.home() / ".codex")
    paths = Paths(Path(home_value).expanduser().resolve())
    try:
        args.handler(paths, args)
        return 0
    except EngineError as exc:
        emit(False, error=exc.message, code=exc.code, **exc.details)
        return exc.code
    except KeyboardInterrupt:
        emit(False, error="操作已取消", code=130)
        return 130
    except Exception as exc:
        emit(False, error="配置引擎内部错误", code=70, detail=type(exc).__name__)
        return 70


if __name__ == "__main__":
    raise SystemExit(main())
