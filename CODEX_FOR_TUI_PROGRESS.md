# Codex for TUI Progress Log

## 2026-07-01 Recovery Summary

- Repo: `/workspace/codex-cli-zh-binary-skill.git-tmp`
- Branch: `android-arm64-musl-installer`
- Remote: `gzy3894-png/codex-cli-zh-binary-skill`
- App goal: ReTerminal-based Android app named `Codex for TUI`, package `com.gzy3894.codexfortui`, that boots into Alpine and guides users through Codex install/config.
- Latest known commit before this log: `485135b Improve first-run installer prompts`
- Latest successful Actions run: `28489706531`
- Latest APK: `/workspace/apks/Codex-for-TUI-debug-485135b.apk`
- APK sha256: `f7fe252b62f348c3c673311eafdc27476fbe3813157dd412b49dfcb9b9b2e78b`

## Implemented Before This Log

- Imported upstream ReTerminal source into `android-app/`.
- Renamed app to `Codex for TUI`.
- Changed application id to `com.gzy3894.codexfortui`; debug package is `.debug`.
- Added GitHub Actions remote debug APK build.
- Temporarily lowered compile/target SDK to 36 because SDK 37 was unavailable in Actions.
- Added APK assets:
  - `codex-for-tui-bootstrap.sh`
  - `install-reterminal-alpine.sh`
  - `codex-local-resume.sh`
  - `init.sh`
- Added Alpine bootstrap flow:
  - If `codex` exists, start it.
  - If install is incomplete, resume local config.
  - Otherwise run the installer.
- Added first-run installer prompts, dependency profile selection, downloader selection, retry/resume parameters, and `NOTICE.txt` placeholder.

## Current User-Reported Problems

- In a no-proxy failed first install path, reopening the app shows:
  - `Error relocating id: renameat2: symbol not found`
  - `Error relocating mkdir: renameat2: symbol not found`
  - architecture warning reports `unknown`
- The previous build was not tested deeply enough on failure/reopen paths.
- Default announcement URL should not point directly at the user's repository.
- First-run prompts are too noisy.
- Before switching into a new prompt/menu, clear the screen.
- Estimated downloads should show resource names plus total size, not scattered details.

## 2026-07-01 Current Fix Plan

- Prefer BusyBox/system paths before `/usr/bin` so broken Alpine packages do not shadow working built-ins/tools.
- Avoid forcing Alpine 3.24 repositories; use the current Alpine version when possible.
- Remove `coreutils` and `findutils` from default dependency install to avoid replacing BusyBox utilities on fragile Android/proot Alpine roots.
- Replace `id -u` checks with a safer helper that survives broken external `id`.
- Simplify first-run download plan and remove default repo-backed notice URL.
- Sync script changes into APK assets before building.

## 2026-07-01 Fix Work In Progress

- Added this progress log so future turns can continue from a concrete file.
- Started fixing the failed reinstall path by preferring `/bin:/sbin` before `/usr/bin`.
- Removed the default GitHub-backed announcement URL; it is now only shown if `CODEX_FOR_TUI_NOTICE_URL` is explicitly set.
- Simplified first-run text to resource names plus total estimated size.
- Changed installer dependency defaults to avoid installing `coreutils`/`findutils` unless a later explicit need appears.
- Rechecked remaining fragile `id -u` calls and found one in the installer persist-path code plus one in `codex-local-resume.sh`.
- Replaced those checks with `is_root` in both source scripts and APK asset copies so failed install/reopen/resume paths do not call a broken external `id`.
- Ran syntax checks for:
  - `android-arm64-musl/install-reterminal-alpine.sh`
  - `android-app/core/main/src/main/assets/install-reterminal-alpine.sh`
  - `android-arm64-musl/codex-local-resume.sh`
  - `android-app/core/main/src/main/assets/codex-local-resume.sh`
  - `android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh`
- Re-ran keyword scan for `id -u`, `coreutils`, `findutils`, hardcoded `v3.24`, notice URL, and repo raw URL. Remaining matches are expected: `REPO_RAW` is still the Codex archive source, and `NOTICE_URL` is blank by default.
