#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/openai/codex.git"
WORK_ROOT="${CODEX_ZH_WORK_ROOT:-$HOME/.cache/codex-cli-zh}"
SOURCE_ROOT=""
REPO_REF=""
CARGO_TARGET_DIR=""
TARGET_TRIPLE=""
SKIP_BUILD=0
DRY_RUN=0
INSTALL=0
INSTALL_DIR="$HOME/.local/bin"
INSTALL_NAME="codex-zh"

usage() {
  cat <<'USAGE'
Build a Chinese-localized Codex CLI from source on macOS.

Usage:
  build-codex-cli-zh-macos.sh [options]

Options:
  --repo-ref REF          Upstream Codex tag/ref, for example rust-v0.142.4.
  --source-root PATH      Existing checkout containing codex-rs.
  --repo-url URL          Codex upstream repository URL.
  --work-root PATH        Clone/cache root. Default: ~/.cache/codex-cli-zh.
  --cargo-target-dir PATH Cargo target dir. Default: <work-root>/target-zh-<version>.
  --target TRIPLE         Optional Rust target triple, for example aarch64-apple-darwin.
  --skip-build            Patch source only.
  --dry-run               Print the plan only.
  --install               Copy the built binary to ~/.local/bin/codex-zh by default.
  --install-dir PATH      Install directory when --install is set.
  --install-name NAME     Installed binary name when --install is set.
  -h, --help              Show this help.

Notes:
  This script is for macOS native builds. It does not modify the npm codex wrapper.
  Use the PowerShell workflow on Windows, and the android-musl skill for aarch64 musl.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-ref) REPO_REF="${2:?missing value for --repo-ref}"; shift 2 ;;
    --source-root) SOURCE_ROOT="${2:?missing value for --source-root}"; shift 2 ;;
    --repo-url) REPO_URL="${2:?missing value for --repo-url}"; shift 2 ;;
    --work-root) WORK_ROOT="${2:?missing value for --work-root}"; shift 2 ;;
    --cargo-target-dir) CARGO_TARGET_DIR="${2:?missing value for --cargo-target-dir}"; shift 2 ;;
    --target) TARGET_TRIPLE="${2:?missing value for --target}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --install) INSTALL=1; shift ;;
    --install-dir) INSTALL_DIR="${2:?missing value for --install-dir}"; shift 2 ;;
    --install-name) INSTALL_NAME="${2:?missing value for --install-name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

need_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found on PATH: $1" >&2
    exit 1
  fi
}

resolve_python() {
  local candidates=()
  if [[ -n "${PYTHON:-}" ]]; then
    candidates+=("$PYTHON")
  fi
  candidates+=(python3 python)

  local candidate
  for candidate in "${candidates[@]}"; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
      continue
    fi
    if "$candidate" --version >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  return 1
}

detect_codex_version() {
  if command -v codex >/dev/null 2>&1; then
    codex --version 2>/dev/null | sed -nE 's/.*codex-cli[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1
  fi
}

safe_ref_name() {
  printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]+/-/g'
}

version_label_from_ref() {
  local ref="$1"
  if [[ "$ref" == rust-v* ]]; then
    printf '%s' "${ref#rust-v}"
  else
    safe_ref_name "$ref"
  fi
}

need_tool git
need_tool cargo
PYTHON_BIN="$(resolve_python || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  echo "Required tool not found on PATH: python3 or python. You can also set PYTHON=/path/to/python3." >&2
  exit 1
fi

if [[ -z "$REPO_REF" ]]; then
  detected_version="$(detect_codex_version || true)"
  if [[ -n "${detected_version:-}" ]]; then
    REPO_REF="rust-v$detected_version"
  else
    REPO_REF="main"
  fi
fi

VERSION_LABEL="$(version_label_from_ref "$REPO_REF")"
if [[ -z "$CARGO_TARGET_DIR" ]]; then
  CARGO_TARGET_DIR="$WORK_ROOT/target-zh-$VERSION_LABEL"
fi
if [[ -z "$SOURCE_ROOT" ]]; then
  SOURCE_ROOT="$WORK_ROOT/codex-$(safe_ref_name "$REPO_REF")"
fi

cat <<PLAN
== Plan ==
Repo ref:      $REPO_REF
Repo URL:      $REPO_URL
Work root:     $WORK_ROOT
Source root:   $SOURCE_ROOT
Cargo target:  $CARGO_TARGET_DIR
Rust target:   ${TARGET_TRIPLE:-host}
Python:        $PYTHON_BIN
Skip build:    $SKIP_BUILD
Install:       $INSTALL
PLAN

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run: no source files, build artifacts, or install targets were changed."
  exit 0
fi

mkdir -p "$WORK_ROOT" "$CARGO_TARGET_DIR"

if [[ ! -d "$SOURCE_ROOT" ]]; then
  git clone --filter=blob:none --sparse --depth 1 --branch "$REPO_REF" "$REPO_URL" "$SOURCE_ROOT"
  git -C "$SOURCE_ROOT" sparse-checkout set codex-rs
else
  echo "Using existing source: $SOURCE_ROOT"
fi

export SOURCE_ROOT
export SCRIPT_DIR

"$PYTHON_BIN" <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path


script_dir = Path(os.environ["SCRIPT_DIR"]).resolve()
source_root = Path(os.environ["SOURCE_ROOT"]).resolve()

if (source_root / "codex-rs" / "tui" / "src").is_dir():
    repo_root = source_root
    codex_rs = source_root / "codex-rs"
elif (source_root / "tui" / "src").is_dir():
    codex_rs = source_root
    repo_root = source_root.parent
else:
    raise SystemExit(f"Could not find codex-rs under {source_root}")


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n")


def quoted(text: str) -> str:
    return '"' + text + '"'


def raw_rust(text: str) -> str:
    return 'r#"' + text.replace(r"\"", '"') + '"#'


def source_pairs(path: Path, from_text: str, to_text: str) -> list[tuple[str, str]]:
    suffix = path.suffix.lower()
    if suffix in {".rs", ".json"}:
        pairs = [(quoted(from_text), quoted(to_text))]
        if suffix == ".rs":
            pairs.append((raw_rust(from_text), raw_rust(to_text)))
        return list(dict.fromkeys(pairs))
    return [(from_text, to_text)]


def resolve_target(relative: str) -> Path:
    rel = Path(relative.replace("\\", "/"))
    if rel.parts and rel.parts[0] == "codex-rs":
        target = repo_root / rel
    else:
        target = codex_rs / rel
    if not target.exists():
        raise FileNotFoundError(f"Target file not found for {relative}: {target}")
    return target


def apply_deep_map(map_path: Path) -> tuple[int, int]:
    data = json.loads(map_path.read_text(encoding="utf-8"))
    changed = 0
    already = 0
    for target in data["targets"]:
        file_path = resolve_target(target["path"])
        raw = file_path.read_text(encoding="utf-8")
        newline = "\r\n" if "\r\n" in raw else "\n"
        content = normalize(raw)
        replacements = sorted(
            target["replacements"],
            key=lambda item: (-len(item["from"]), item["from"]),
        )
        missing: list[str] = []
        for item in replacements:
            from_text = normalize(str(item["from"]))
            to_text = normalize(str(item["to"]))
            pairs = source_pairs(file_path, from_text, to_text)
            count = sum(content.count(src) for src, _ in pairs)
            if count == 0:
                if any(dst in content for _, dst in pairs):
                    already += 1
                    continue
                missing.append(from_text)
                continue
            for src, dst in pairs:
                occurrences = content.count(src)
                if occurrences:
                    content = content.replace(src, dst)
                    changed += occurrences
        if missing:
            sample = "\n  - ".join(missing[:8])
            raise RuntimeError(
                f"Missing expected English strings in {file_path}; update the map:\n  - {sample}"
            )
        file_path.write_text(content.replace("\n", newline), encoding="utf-8")
    return changed, already


def apply_slash_map(map_path: Path) -> tuple[int, int]:
    slash_file = codex_rs / "tui" / "src" / "slash_command.rs"
    items = json.loads(map_path.read_text(encoding="utf-8"))
    content = slash_file.read_text(encoding="utf-8")
    changed = 0
    already = 0
    missing: list[str] = []
    for item in items:
        from_text = str(item["from"])
        to_text = str(item["to"])
        count = content.count(from_text)
        if count == 0:
            if to_text in content:
                already += 1
                continue
            missing.append(from_text)
            continue
        content = content.replace(from_text, to_text)
        changed += count
    if missing:
        sample = "\n  - ".join(missing[:8])
        raise RuntimeError(
            f"Missing expected slash command strings in {slash_file}; update the map:\n  - {sample}"
        )
    slash_file.write_text(content, encoding="utf-8")
    return changed, already


slash_changed, slash_already = apply_slash_map(script_dir / "slash-command-translations.zh.json")
deep_changed, deep_already = apply_deep_map(script_dir / "deep-translations.zh.json")
print(f"Slash replacements: changed={slash_changed} already={slash_already}")
print(f"Deep replacements:  changed={deep_changed} already={deep_already}")
print(f"Patched source:     {codex_rs}")
PY

if [[ "$SKIP_BUILD" -eq 1 ]]; then
  echo "Skipped build."
  exit 0
fi

export CARGO_TARGET_DIR
build_args=(build --release -p codex-cli)
if [[ -n "$TARGET_TRIPLE" ]]; then
  rustup target add "$TARGET_TRIPLE" >/dev/null
  build_args+=(--target "$TARGET_TRIPLE")
fi

(cd "$SOURCE_ROOT/codex-rs" && cargo "${build_args[@]}")

if [[ -n "$TARGET_TRIPLE" ]]; then
  built="$CARGO_TARGET_DIR/$TARGET_TRIPLE/release/codex"
else
  built="$CARGO_TARGET_DIR/release/codex"
fi

if [[ ! -x "$built" ]]; then
  echo "Build finished but expected binary was not found or executable: $built" >&2
  exit 1
fi

"$built" --version || true
echo "Built binary: $built"

if [[ "$INSTALL" -eq 1 ]]; then
  mkdir -p "$INSTALL_DIR"
  cp "$built" "$INSTALL_DIR/$INSTALL_NAME"
  chmod +x "$INSTALL_DIR/$INSTALL_NAME"
  echo "Installed: $INSTALL_DIR/$INSTALL_NAME"
fi
