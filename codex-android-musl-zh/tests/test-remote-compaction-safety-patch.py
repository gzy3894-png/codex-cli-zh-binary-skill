#!/usr/bin/env python3
"""Fixture tests for the remote compaction safety source patch."""

from __future__ import annotations

import hashlib
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PATCHER = (
    ROOT
    / "codex-android-musl-zh/scripts/apply-remote-compaction-safety.py"
)

PROVIDER_SOURCE = """impl ModelProviderInfo {
    pub fn supports_remote_compaction(&self) -> bool {
        self.is_openai() || is_azure_responses_provider(&self.name, self.base_url.as_deref())
    }
}
"""

PROVIDER_TESTS = """#[test]
fn test_supports_remote_compaction_for_openai() {
    let provider = ModelProviderInfo::create_openai_provider(/*base_url*/ None);
    assert!(provider.supports_remote_compaction());
}

#[test]
fn test_personal_access_token_uses_chatgpt_codex_base_url() {
    assert!(true);
}

#[test]
fn test_supports_remote_compaction_for_azure_name() {
    assert!(true);
}
"""


def digest(paths: list[Path]) -> str:
    result = hashlib.sha256()
    for path in paths:
        result.update(path.read_bytes())
    return result.hexdigest()


def create_fixture(root: Path, provider_source: str = PROVIDER_SOURCE) -> list[Path]:
    source_dir = root / "codex-rs/model-provider-info/src"
    source_dir.mkdir(parents=True)
    provider = source_dir / "lib.rs"
    tests = source_dir / "model_provider_info_tests.rs"
    provider.write_text(provider_source, encoding="utf-8")
    tests.write_text(PROVIDER_TESTS, encoding="utf-8")
    return [provider, tests]


def run_patcher(source_root: Path, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "python3",
            str(PATCHER),
            "--source-root",
            str(source_root),
        ],
        check=check,
        capture_output=True,
        text=True,
    )


def test_success_and_idempotency() -> None:
    with tempfile.TemporaryDirectory(prefix="codex-remote-compact-patch.") as tmp:
        source_root = Path(tmp)
        provider, tests = create_fixture(source_root)
        run_patcher(source_root)
        first = digest([provider, tests])
        run_patcher(source_root)
        second = digest([provider, tests])
        assert first == second, "remote compaction patch must be idempotent"

        provider_text = provider.read_text(encoding="utf-8")
        tests_text = tests.read_text(encoding="utf-8")
        assert "(self.is_openai() && self.requires_openai_auth)" in provider_text
        assert "self.is_openai() || is_azure_responses_provider" not in provider_text
        assert "is_azure_responses_provider" in provider_text
        assert (
            "test_openai_named_third_party_provider_uses_local_compaction"
            in tests_text
        )
        assert 'wire_api = "responses"' in tests_text
        assert "requires_openai_auth = false" in tests_text
        assert "assert!(!provider.supports_remote_compaction())" in tests_text


def test_anchor_drift_fails_closed() -> None:
    with tempfile.TemporaryDirectory(prefix="codex-remote-compact-drift.") as tmp:
        source_root = Path(tmp)
        create_fixture(
            source_root,
            PROVIDER_SOURCE.replace(
                "self.is_openai() || is_azure_responses_provider",
                "self.is_openai() && is_azure_responses_provider",
            ),
        )
        result = run_patcher(source_root, check=False)
        assert result.returncode != 0
        assert "anchor missing" in result.stderr


def main() -> int:
    test_success_and_idempotency()
    test_anchor_drift_fails_closed()
    print("remote compaction safety patch fixture: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
