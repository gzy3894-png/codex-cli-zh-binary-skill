#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE="$ROOT_DIR/android-arm64-musl/libexec/codex-config-engine.py"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-v2-parser.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -x "$ENGINE" ] || fail "configuration engine is not executable"
[ -n "$CODEX_BIN" ] && [ -x "$CODEX_BIN" ] ||
  fail "Codex binary is unavailable; set CODEX_BIN to the binary under test"

printf '%s\n' \
  '{"data":[{"id":"gpt-5.4"},{"id":"gpt-5.5"},{"id":"gpt-5.6-sol"},{"id":"gpt-5.6-terra"},{"id":"gpt-5.6-luna"},{"id":"codex-auto-review"},{"id":"codex-auto-fast"},{"id":"vendor-unknown"}]}' \
  > "$TMP_ROOT/provider.json"

PYTHONNOUSERSITE=1 python3 "$ENGINE" \
  --codex-home "$TMP_ROOT" \
  catalog build \
  --provider-json "$TMP_ROOT/provider.json" \
  --output "$TMP_ROOT/model_catalog.json" \
  --offline > "$TMP_ROOT/catalog-build.json"

PYTHONNOUSERSITE=1 python3 "$ENGINE" \
  --codex-home "$TMP_ROOT" \
  profile create \
  --name parser-smoke \
  --mode third_party \
  --provider-name ParserSmoke \
  --base-url https://example.invalid/v1 \
  --model gpt-5.6-sol \
  --reasoning-effort high \
  --catalog-file "$TMP_ROOT/model_catalog.json" \
  --activate > "$TMP_ROOT/profile-create.json"

CODEX_HOME="$TMP_ROOT" "$CODEX_BIN" debug models \
  > "$TMP_ROOT/codex-models.json" \
  2> "$TMP_ROOT/codex-models.err" ||
  {
    sed -n '1,120p' "$TMP_ROOT/codex-models.err" >&2 || true
    fail "Codex rejected the generated config or model catalog"
  }

python3 - "$TMP_ROOT/codex-models.json" "$TMP_ROOT/config.toml" <<'PY'
import json
import sys
from pathlib import Path

raw = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
models = raw.get("models", raw) if isinstance(raw, dict) else raw
by_slug = {
    item.get("slug"): item
    for item in models
    if isinstance(item, dict) and item.get("slug")
}

required = [
    "gpt-5.4",
    "gpt-5.5",
    "gpt-5.6-sol",
    "gpt-5.6-terra",
    "gpt-5.6-luna",
    "codex-auto-review",
    "codex-auto-fast",
    "vendor-unknown",
]
missing = [slug for slug in required if slug not in by_slug]
if missing:
    raise SystemExit(f"missing parsed models: {missing}")

sol = by_slug["gpt-5.6-sol"]
if sol.get("context_window") != 372000:
    raise SystemExit(
        f"unexpected gpt-5.6-sol context window: {sol.get('context_window')}"
    )
efforts = [
    item.get("effort")
    for item in sol.get("supported_reasoning_levels", [])
    if isinstance(item, dict)
]
if efforts[-2:] != ["max", "ultra"]:
    raise SystemExit(f"unexpected gpt-5.6-sol reasoning levels: {efforts}")
if sol.get("auto_compact_token_limit") != 297600:
    raise SystemExit(
        f"unexpected gpt-5.6-sol compact limit: {sol.get('auto_compact_token_limit')}"
    )

for slug in ("codex-auto-review", "codex-auto-fast"):
    if by_slug[slug].get("visibility") != "hide":
        raise SystemExit(
            f"auto helper model remains visible in /model: {slug}"
        )

unknown = by_slug["vendor-unknown"]
if unknown.get("context_window") != 272000:
    raise SystemExit(
        f"unexpected unknown-model context: {unknown.get('context_window')}"
    )
if unknown.get("auto_compact_token_limit") != 217600:
    raise SystemExit(
        f"unexpected unknown-model compact limit: {unknown.get('auto_compact_token_limit')}"
    )
if unknown.get("default_reasoning_level") != "medium":
    raise SystemExit(
        f"unexpected unknown-model reasoning default: {unknown.get('default_reasoning_level')}"
    )
unknown_efforts = [
    item.get("effort")
    for item in unknown.get("supported_reasoning_levels", [])
    if isinstance(item, dict)
]
if unknown_efforts != ["low", "medium", "high", "xhigh"]:
    raise SystemExit(f"unexpected unknown-model reasoning levels: {unknown_efforts}")
if not unknown.get("base_instructions"):
    raise SystemExit("unknown model is missing Codex base instructions")

config = Path(sys.argv[2]).read_text(encoding="utf-8")
if "model_catalog_json = " not in config:
    raise SystemExit("generated config is missing model_catalog_json")
if 'model_reasoning_effort = "high"' not in config:
    raise SystemExit("generated config is missing the selected reasoning effort")

print(f"PASS: Codex parsed {len(models)} generated catalog entries")
print("PASS: gpt-5.6-sol exposes max and ultra")
print("PASS: codex-auto helper models are hidden from /model")
print("PASS: unknown models use 272k, 80% compact, and four baseline reasoning levels")
PY
