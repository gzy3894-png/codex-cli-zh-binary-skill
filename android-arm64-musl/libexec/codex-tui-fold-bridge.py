#!/usr/bin/env python3
"""Map Codex session rollout jsonl turn events → session-fold bridge actions.

MVP Runtime Emitter for Codex-for-TUI long-output/fold force path.

Default is dry-run and disabled. Never blocks the agent.

Policy file (optional): $PREFIX/local/ops/session-fold-bridge.policy
  enabled=0|1
  mode=dry-run|apply
  min_interval_ms=0
  title_prefix=turn

Or env:
  CODEX_TUI_FOLD_BRIDGE=0|1
  CODEX_TUI_FOLD_BRIDGE_MODE=dry-run|apply
  CODEX_HOME, PREFIX (for locating sessions / writing bridge via codex-session)

Commands:
  map-file <rollout.jsonl>     # offline map, print actions
  tail-once <rollout.jsonl>    # read from offset file, emit new actions
  discover-active              # list newest rollout-*.jsonl under CODEX_HOME/sessions
  watch [rollout.jsonl]        # poll tail-once (optional path; default newest)
  status                       # show policy + state
  self-test                    # synthetic events smoke
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.I,
)


def eprint(*a: Any) -> None:
    print(*a, file=sys.stderr)


def find_prefix() -> Optional[Path]:
    for key in ("PREFIX", "CODEX_FOR_TUI_PREFIX"):
        v = os.environ.get(key)
        if v:
            p = Path(v)
            if p.exists():
                return p
    # common app local
    cand = Path("/data/user/0/com.gzy3894.codexfortui")
    if cand.exists():
        return cand
    return None


def codex_home() -> Path:
    v = os.environ.get("CODEX_HOME")
    if v:
        return Path(v).expanduser()
    # alpine default under app
    pref = find_prefix()
    if pref:
        p = pref / "local/alpine/root/.codex"
        if p.exists():
            return p
    return Path.home() / ".codex"


def policy_path() -> Path:
    pref = find_prefix()
    if pref:
        return pref / "local/ops/session-fold-bridge.policy"
    return Path("/tmp/session-fold-bridge.policy")


def state_dir() -> Path:
    home = codex_home()
    d = home / "install-state" / "fold-bridge"
    d.mkdir(parents=True, exist_ok=True)
    return d


def read_policy() -> Dict[str, str]:
    defaults = {
        "enabled": os.environ.get("CODEX_TUI_FOLD_BRIDGE", "0"),
        "mode": os.environ.get("CODEX_TUI_FOLD_BRIDGE_MODE", "dry-run"),
        "min_interval_ms": "0",
        "title_prefix": "turn",
        "shell_guard": "1",
    }
    path = policy_path()
    if not path.exists():
        return defaults
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return defaults
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        defaults[k.strip()] = v.strip()
    # env overrides file
    if "CODEX_TUI_FOLD_BRIDGE" in os.environ:
        defaults["enabled"] = os.environ["CODEX_TUI_FOLD_BRIDGE"]
    if "CODEX_TUI_FOLD_BRIDGE_MODE" in os.environ:
        defaults["mode"] = os.environ["CODEX_TUI_FOLD_BRIDGE_MODE"]
    return defaults


def enabled(pol: Dict[str, str]) -> bool:
    return pol.get("enabled", "0").strip() in {"1", "true", "yes", "on"}


def parse_line(line: str) -> Optional[Dict[str, Any]]:
    line = line.strip()
    if not line:
        return None
    try:
        o = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(o, dict):
        return None
    return o


def extract_turn_event(obj: Dict[str, Any]) -> Optional[Tuple[str, str, Dict[str, Any]]]:
    """Return (action, run_id, meta) if this line is a turn boundary.

    action in {start, done, fail}
    """
    t = obj.get("type")
    pl = obj.get("payload")
    if not isinstance(pl, dict):
        return None
    pt = pl.get("type")
    turn_id = pl.get("turn_id") or pl.get("turnId")
    if not isinstance(turn_id, str) or not turn_id:
        # some events nest differently
        return None
    # normalize run id for bridge (safe chars)
    run_id = re.sub(r"[^A-Za-z0-9._-]", "-", turn_id)[:80]
    if pt == "task_started":
        return ("start", run_id, {"turn_id": turn_id, "raw": pt})
    if pt == "task_complete":
        return ("done", run_id, {"turn_id": turn_id, "raw": pt, "duration_ms": pl.get("duration_ms")})
    if pt == "turn_aborted":
        return (
            "fail",
            run_id,
            {"turn_id": turn_id, "raw": pt, "reason": pl.get("reason"), "duration_ms": pl.get("duration_ms")},
        )
    return None


def map_file(path: Path) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = []
    open_runs: Dict[str, Dict[str, Any]] = {}
    with path.open(encoding="utf-8", errors="replace") as f:
        for lineno, line in enumerate(f, 1):
            obj = parse_line(line)
            if not obj:
                continue
            # only event_msg carries task_* in observed rollouts; still try all
            ev = extract_turn_event(obj)
            if not ev:
                continue
            action, run_id, meta = ev
            rec = {
                "action": action,
                "run_id": run_id,
                "line": lineno,
                "meta": meta,
                "ts": obj.get("timestamp"),
            }
            if action == "start":
                open_runs[run_id] = rec
            elif action in {"done", "fail"}:
                open_runs.pop(run_id, None)
            actions.append(rec)
    return actions


def format_cli(action: str, run_id: str, pol: Dict[str, str], meta: Dict[str, Any]) -> str:
    prefix = pol.get("title_prefix", "turn")
    if action == "start":
        title = f"{prefix} {run_id[:8]}"
        return f'codex-session start --run {run_id} "{title}"'
    if action == "done":
        summary = "task_complete"
        if meta.get("duration_ms") is not None:
            summary = f"task_complete {meta.get('duration_ms')}ms"
        return f'codex-session done {run_id} "{summary}"'
    if action == "fail":
        reason = meta.get("reason") or "aborted"
        return f'codex-session fail {run_id} "{reason}"'
    return f"# unknown {action} {run_id}"


def which_codex_session() -> Optional[str]:
    for d in os.environ.get("PATH", "").split(os.pathsep):
        cand = Path(d) / "codex-session"
        if cand.is_file() and os.access(cand, os.X_OK):
            return str(cand)
    pref = find_prefix()
    if pref:
        cand = pref / "local/bin/codex-session"
        if cand.is_file():
            return str(cand)
    return None


def apply_action(action: str, run_id: str, pol: Dict[str, str], meta: Dict[str, Any]) -> int:
    import subprocess

    cli = which_codex_session()
    if not cli:
        eprint("codex-session not found; cannot apply")
        return 2
    if action == "start":
        title = f"{pol.get('title_prefix', 'turn')} {run_id[:8]}"
        cmd = [cli, "start", "--run", run_id, title]
    elif action == "done":
        summary = "task_complete"
        if meta.get("duration_ms") is not None:
            summary = f"task_complete {meta.get('duration_ms')}ms"
        cmd = [cli, "done", run_id, summary]
    elif action == "fail":
        reason = str(meta.get("reason") or "aborted")
        cmd = [cli, "fail", run_id, reason]
    else:
        return 0
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except Exception as exc:  # noqa: BLE001
        eprint("apply failed", exc)
        return 1
    if r.returncode != 0:
        eprint("apply rc", r.returncode, r.stderr[:300])
    return r.returncode


def cmd_map_file(path: Path, pol: Dict[str, str]) -> int:
    if not path.exists():
        eprint("missing", path)
        return 2
    actions = map_file(path)
    summary = {
        "file": str(path),
        "actions": len(actions),
        "starts": sum(1 for a in actions if a["action"] == "start"),
        "dones": sum(1 for a in actions if a["action"] == "done"),
        "fails": sum(1 for a in actions if a["action"] == "fail"),
        "enabled": enabled(pol),
        "mode": pol.get("mode"),
    }
    try:
        print(json.dumps({"summary": summary}, ensure_ascii=False))
        for a in actions:
            line = format_cli(a["action"], a["run_id"], pol, a.get("meta") or {})
            print(f"L{a['line']}\t{a['action']}\t{a['run_id']}\t{line}")
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except Exception:
            pass
        return 0
    return 0


def cmd_self_test() -> int:
    samples = [
        {
            "timestamp": "2026-07-13T00:00:00Z",
            "type": "event_msg",
            "payload": {"type": "task_started", "turn_id": "019f-test-turn-1"},
        },
        {
            "timestamp": "2026-07-13T00:00:01Z",
            "type": "event_msg",
            "payload": {"type": "task_complete", "turn_id": "019f-test-turn-1", "duration_ms": 1000},
        },
        {
            "timestamp": "2026-07-13T00:00:02Z",
            "type": "event_msg",
            "payload": {"type": "task_started", "turn_id": "019f-test-turn-2"},
        },
        {
            "timestamp": "2026-07-13T00:00:03Z",
            "type": "event_msg",
            "payload": {"type": "turn_aborted", "turn_id": "019f-test-turn-2", "reason": "interrupted"},
        },
        # noise
        {
            "timestamp": "2026-07-13T00:00:04Z",
            "type": "response_item",
            "payload": {"type": "reasoning", "text": "x"},
        },
    ]
    got = []
    for o in samples:
        ev = extract_turn_event(o)
        if ev:
            got.append(ev[0])
    expect = ["start", "done", "start", "fail"]
    ok = got == expect
    print(json.dumps({"ok": ok, "got": got, "expect": expect}, ensure_ascii=False))
    return 0 if ok else 1


def cmd_status(pol: Dict[str, str]) -> int:
    out = {
        "policy_path": str(policy_path()),
        "policy": pol,
        "enabled": enabled(pol),
        "codex_home": str(codex_home()),
        "prefix": str(find_prefix()) if find_prefix() else None,
        "codex_session": which_codex_session(),
        "state_dir": str(state_dir()),
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def cmd_tail_once(path: Path, pol: Dict[str, str]) -> int:
    """Process new bytes since last offset; dry-run or apply per policy."""
    if not path.exists():
        eprint("missing", path)
        return 2
    st = state_dir() / (path.name + ".offset")
    offset = 0
    if st.exists():
        try:
            offset = int(st.read_text(encoding="utf-8").strip() or "0")
        except ValueError:
            offset = 0
    size = path.stat().st_size
    if offset > size:
        offset = 0  # rotated/truncated
    actions_out: List[Dict[str, Any]] = []
    with path.open("rb") as f:
        f.seek(offset)
        data = f.read()
        new_offset = f.tell()
    text = data.decode("utf-8", errors="replace")
    for line in text.splitlines():
        obj = parse_line(line)
        if not obj:
            continue
        ev = extract_turn_event(obj)
        if not ev:
            continue
        action, run_id, meta = ev
        rec = {"action": action, "run_id": run_id, "meta": meta, "cli": format_cli(action, run_id, pol, meta)}
        actions_out.append(rec)
        if enabled(pol) and pol.get("mode") == "apply":
            apply_action(action, run_id, pol, meta)
    st.write_text(str(new_offset), encoding="utf-8")
    print(
        json.dumps(
            {
                "file": str(path),
                "offset_from": offset,
                "offset_to": new_offset,
                "actions": actions_out,
                "enabled": enabled(pol),
                "mode": pol.get("mode"),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def discover_rollouts(home: Optional[Path] = None) -> List[Path]:
    """Find rollout-*.jsonl under CODEX_HOME/sessions, newest mtime first."""
    root = (home or codex_home()) / "sessions"
    if not root.is_dir():
        return []
    found: List[Path] = []
    try:
        for p in root.rglob("rollout-*.jsonl"):
            if p.is_file():
                found.append(p)
    except OSError:
        return []
    found.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0.0, reverse=True)
    return found


def cmd_discover_active(pol: Dict[str, str], limit: int = 5) -> int:
    files = discover_rollouts()
    active = files[: max(1, limit)]
    out = {
        "codex_home": str(codex_home()),
        "count": len(files),
        "active": [
            {
                "path": str(p),
                "mtime": p.stat().st_mtime if p.exists() else None,
                "size": p.stat().st_size if p.exists() else None,
            }
            for p in active
        ],
        "enabled": enabled(pol),
        "mode": pol.get("mode"),
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def cmd_watch(
    pol: Dict[str, str],
    path: Optional[Path],
    interval_ms: int,
    max_iters: int,
) -> int:
    """Poll tail-once on active or explicit rollout. Best-effort; never raises out.

    Default does not require enabled=1: dry-run still advances offsets and prints.
    """
    if interval_ms < 200:
        interval_ms = 200
    iters = 0
    while max_iters <= 0 or iters < max_iters:
        iters += 1
        target = path
        if target is None:
            files = discover_rollouts()
            target = files[0] if files else None
        if target is None:
            print(
                json.dumps(
                    {
                        "watch": True,
                        "iter": iters,
                        "file": None,
                        "actions": [],
                        "note": "no rollout found",
                        "enabled": enabled(pol),
                        "mode": pol.get("mode"),
                    },
                    ensure_ascii=False,
                )
            )
        else:
            # reuse tail-once logic but always print one JSON object per tick
            rc = cmd_tail_once(Path(target), pol)
            if rc not in (0,):
                eprint("tail-once rc", rc, target)
        time.sleep(interval_ms / 1000.0)
        # re-read policy each tick so flag flips without restart
        pol = read_policy()
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="codex-tui-fold-bridge")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_map = sub.add_parser("map-file")
    p_map.add_argument("path")
    p_tail = sub.add_parser("tail-once")
    p_tail.add_argument("path")
    p_disc = sub.add_parser("discover-active")
    p_disc.add_argument("--limit", type=int, default=5)
    p_watch = sub.add_parser("watch")
    p_watch.add_argument("path", nargs="?", default=None, help="optional rollout.jsonl; default=newest")
    p_watch.add_argument("--interval-ms", type=int, default=1500)
    p_watch.add_argument(
        "--max-iters",
        type=int,
        default=0,
        help="0 = forever; smoke uses small N",
    )
    sub.add_parser("status")
    sub.add_parser("self-test")
    args = parser.parse_args(argv)
    pol = read_policy()
    if args.cmd == "map-file":
        return cmd_map_file(Path(args.path), pol)
    if args.cmd == "tail-once":
        return cmd_tail_once(Path(args.path), pol)
    if args.cmd == "discover-active":
        return cmd_discover_active(pol, limit=args.limit)
    if args.cmd == "watch":
        return cmd_watch(
            pol,
            Path(args.path) if args.path else None,
            interval_ms=args.interval_ms,
            max_iters=args.max_iters,
        )
    if args.cmd == "status":
        return cmd_status(pol)
    if args.cmd == "self-test":
        return cmd_self_test()
    return 2


if __name__ == "__main__":
    sys.exit(main())
