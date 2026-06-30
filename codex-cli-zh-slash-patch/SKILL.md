---
name: codex-cli-zh-slash-patch
description: Rebuild and optionally install a patched OpenAI Codex CLI binary whose slash-command popup descriptions are localized into Chinese. Use when the user wants to 汉化 Codex CLI / command descriptions, patch slash command help text, reapply Chinese descriptions after a Codex update, or replace English popup strings such as "/model choose what model and reasoning effort to use".
---

# Codex CLI Slash Command Chinese Patch

## Overview

Use this skill to patch the Rust source file that owns Codex CLI slash-command popup descriptions, build `codex.exe`, and optionally replace the npm-installed Windows native binary with a backed-up patched copy.

Do not binary-patch `codex.exe`; Chinese UTF-8 strings are different lengths and can corrupt the executable. Patch source and rebuild.

## Quick Start

Run the helper script from this skill directory:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-slash-patch\scripts\patch-codex-slash-zh.ps1" -DryRun
```

Prepare a patched binary without replacing the active install:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-slash-patch\scripts\patch-codex-slash-zh.ps1"
```

Patch, build, back up the current binary, and install the rebuilt `codex.exe`:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-slash-patch\scripts\patch-codex-slash-zh.ps1" -Install
```

Patch, build, and install by editing the small Node wrapper so `codex` starts the rebuilt E-drive binary. Use this when the active Codex process locks the npm-installed `codex.exe`:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-slash-patch\scripts\patch-codex-slash-zh.ps1" -Install -UseWrapperOverride
```

After install, restart Codex CLI before checking the slash-command popup. The running process keeps using the old binary until restart.

## Workflow

1. Run `-DryRun` first to confirm the current Codex version, target git tag, toolchain, and install path.
2. Edit `scripts/slash-command-translations.zh.json` only if the Chinese wording needs adjustment.
3. Run without `-Install` to clone the matching `rust-vX.Y.Z` source, patch `codex-rs/tui/src/slash_command.rs`, and build `codex.exe`.
4. Run with `-Install` when the user is ready to replace the installed native binary. The script writes a backup under `%USERPROFILE%\.codex\backups\cli-zh-slash\`.
5. If Windows reports the target `codex.exe` is locked, the script falls back to a Node wrapper override that points `codex` at the rebuilt E-drive binary. You can also request this directly with `-UseWrapperOverride`.

## Script Notes

- Default repo ref is derived from `codex --version`; for `codex-cli 0.142.0`, it uses `rust-v0.142.0`.
- Override the ref with `-RepoRef rust-v0.142.1` or a branch name when needed.
- Use `-SourceRoot <path>` to patch an existing Codex checkout instead of cloning.
- The default build checkout is `E:\cz` to keep source, Cargo target output, and V8 intermediates off the C drive.
- The script sets a usable `PYTHON` for Rust/V8 build scripts when possible. Override it with `-PythonExe <path>` if needed.
- If the V8 prebuilt archive download was interrupted but a valid `.gz` remains, pass `-RustyV8Archive <path-to-rusty_v8_*.lib.gz-or-tmp>` to reuse it.
- You can override `-CargoHome` and `-CargoTargetDir` if you want different non-C locations.
- Use `-UseWrapperOverride` to leave the signed vendor `codex.exe` untouched and instead make `codex.js` prefer the rebuilt binary, for example `E:\cz\target\release\codex.exe`.
- Use `-SkipBuild` only for source-patch testing or when `target\release\codex.exe` already exists.
- The script intentionally fails when expected English strings are missing and their Chinese replacements are not already present. That usually means upstream changed the wording and the JSON map needs review.

## Verification

Use the generated build output and script summary as evidence. For the live UI, the practical check is to restart Codex CLI, type `/`, and confirm descriptions such as `/model` are Chinese.
