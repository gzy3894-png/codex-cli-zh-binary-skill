#!/usr/bin/env python3
"""Disable remote compaction for OpenAI-compatible third-party providers.

Codex 0.144.1 treats every provider named ``OpenAI`` as supporting the
OpenAI-only remote compaction protocol. Codex for TUI intentionally uses that
display name for third-party Responses providers while setting
``requires_openai_auth = false``. Restricting the capability check to the
built-in OpenAI provider keeps ordinary Responses compatibility and makes
third-party providers use local compaction.

The patch is intentionally exact, idempotent, and fail-closed so an upstream
source change cannot silently produce an unsafe binary.
"""

from __future__ import annotations

import argparse
from pathlib import Path


PROVIDER_FILE = Path("codex-rs/model-provider-info/src/lib.rs")
TEST_FILE = Path("codex-rs/model-provider-info/src/model_provider_info_tests.rs")
MARKER = "CODEX_FOR_TUI_REMOTE_COMPACTION_SAFETY"

OLD_CAPABILITY = """    pub fn supports_remote_compaction(&self) -> bool {
        self.is_openai() || is_azure_responses_provider(&self.name, self.base_url.as_deref())
    }
"""

NEW_CAPABILITY = f"""    // {MARKER}
    pub fn supports_remote_compaction(&self) -> bool {{
        (self.is_openai() && self.requires_openai_auth)
            || is_azure_responses_provider(&self.name, self.base_url.as_deref())
    }}
"""

TEST_ANCHOR = """#[test]
fn test_personal_access_token_uses_chatgpt_codex_base_url() {
"""

REGRESSION_TEST = f"""#[test]
fn test_openai_named_third_party_provider_uses_local_compaction() {{
    let provider_toml = r#"
name = "OpenAI"
base_url = "https://relay.example/v1"
wire_api = "responses"
requires_openai_auth = false
        "#;

    let provider: ModelProviderInfo = toml::from_str(provider_toml).unwrap();

    assert_eq!(provider.base_url.as_deref(), Some("https://relay.example/v1"));
    assert_eq!(provider.wire_api, WireApi::Responses);
    assert!(!provider.supports_remote_compaction());
}}

// {MARKER}
"""


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if MARKER in text and new in text:
            return text
        raise SystemExit(f"remote compaction patch anchor missing: {label}")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"remote compaction patch anchor is not unique: {label} count={count}"
        )
    return text.replace(old, new, 1)


def patch_provider(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    patched = replace_once(
        text,
        OLD_CAPABILITY,
        NEW_CAPABILITY,
        "supports_remote_compaction",
    )
    if patched != text:
        path.write_text(patched, encoding="utf-8")


def patch_tests(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if REGRESSION_TEST in text:
        return
    if MARKER in text:
        raise SystemExit("remote compaction patch marker exists without regression test")
    count = text.count(TEST_ANCHOR)
    if count != 1:
        raise SystemExit(
            "remote compaction patch anchor is not unique: "
            f"model provider tests count={count}"
        )
    path.write_text(
        text.replace(TEST_ANCHOR, REGRESSION_TEST + TEST_ANCHOR, 1),
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    provider_path = source_root / PROVIDER_FILE
    test_path = source_root / TEST_FILE
    for path in (provider_path, test_path):
        if not path.is_file():
            raise SystemExit(f"missing Codex source file: {path}")
    patch_provider(provider_path)
    patch_tests(test_path)
    print(f"remote compaction safety patched: {source_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
