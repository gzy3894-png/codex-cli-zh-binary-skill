---
name: codex-cli-zh-deep-patch
description: Source-level Chinese localization workflow for hard-coded OpenAI Codex CLI/TUI prompts beyond slash commands. Use when Codex needs to 汉化 Codex CLI approval prompts, authorization/permission dialogs, MCP elicitation choices, onboarding/auth/API-key screens, app-link setup text, trust-directory prompts, startup hook review text, status-card labels, or to reapply deep Chinese UI patches after a Codex CLI update.
---

# Codex CLI Deep Chinese Patch

## Overview

Use this skill to patch hard-coded Rust strings in Codex CLI/TUI, rebuild `codex.exe`, and optionally make the npm `codex` wrapper start the rebuilt binary. This is source-level localization; do not binary-patch `codex.exe`.

The bundled map targets the high-value TUI surfaces that are not covered by slash-command description patching: approval dialogs, permission grants, network approvals, MCP choices, onboarding sign-in/API-key screens, app setup/browser-return prompts, trusted directory prompts, hook review, and status-card labels.

## Quick Start

Always run dry-run first:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-deep-patch\scripts\patch-codex-cli-zh-deep.ps1" -DryRun -SourceRoot "E:\cz\codex-rust-v0.142.0"
```

Patch an existing checkout without building:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-deep-patch\scripts\patch-codex-cli-zh-deep.ps1" -SourceRoot "E:\cz\codex-rust-v0.142.0" -SkipBuild
```

Patch and rebuild:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-deep-patch\scripts\patch-codex-cli-zh-deep.ps1" -SourceRoot "E:\cz\codex-rust-v0.142.0" -CargoTargetDir "E:\cz\target-zh-deep"
```

Patch, rebuild, and install through the Node wrapper override:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-deep-patch\scripts\patch-codex-cli-zh-deep.ps1" -SourceRoot "E:\cz\codex-rust-v0.142.0" -CargoTargetDir "E:\cz\target-zh-deep" -Install -UseWrapperOverride
```

Restart Codex CLI after rebuilding or installing. A running TUI process keeps using the old binary.

On Windows, do not rebuild into the same target directory that the currently running `codex.exe` came from. A live `codex.exe` locks its own file, so Cargo can compile successfully and still fail at the final replace step with `failed to remove file ... codex.exe` / `拒绝访问。 (os error 5)`. Use an inactive target directory such as `E:\cz\target-zh-deep` or `E:\cz\target-zh-deep-next`.

## Workflow

1. Confirm the local Codex source checkout matches the installed CLI version.
2. Run `-DryRun` and inspect missing/already-translated counts.
3. Edit `scripts/deep-translations.zh.json` if wording needs adjustment.
4. Run with `-SkipBuild` when only testing source patching, or without it to build `codex-cli`.
5. Prefer `-UseWrapperOverride` on Windows when the npm-installed vendor `codex.exe` may be locked. The wrapper override points `codex` at the rebuilt binary, for example `E:\cz\target-zh-deep\release\codex.exe`.
6. Verify source diffs and run `codex --version`. For UI verification, restart Codex CLI and trigger an approval, onboarding, or trust prompt.

## Script Notes

- `-SourceRoot` accepts either the repository root that contains `codex-rs` or the `codex-rs` directory itself.
- `-MapFile` defaults to `scripts/deep-translations.zh.json`.
- `-CargoTargetDir` defaults to `E:\cz\target-zh-deep`; use a target dir that is not currently running. If the active wrapper already points to that target, build into another inactive target directory first.
- `-PythonExe` defaults to `E:\tools\python\python.exe` and is exported only for the build process. This avoids the Windows Store `python` alias breaking `v8` build/download helpers.
- `-SkipBuild` patches source only and exits after reporting counts.
- `-Install` copies or wrapper-installs the rebuilt binary; without `-Install`, it leaves the built binary in the Cargo target directory.
- The script is idempotent: if the English text is absent but the Chinese text is already present, it reports the item as already translated.
- The script fails when expected English text is missing and the Chinese replacement is not present. Treat that as evidence that upstream wording changed and update the JSON map.

## Relationship To Slash Commands

This skill does not duplicate the existing slash-command description patch. Use `codex-cli-zh-slash-patch` for `/model`, `/status`, and similar slash popup descriptions, then use this skill for deeper TUI prompts and authorization flows.

## Verification

Use three levels of evidence:

- Map-level: `-DryRun` reports every target file, replacement count, and missing strings.
- Source-level: `git diff -- tui/src/...` shows Chinese strings in the intended Rust files only.
- Runtime-level: rebuilt `codex.exe --version` works; after restart, interactive prompts render in Chinese.
