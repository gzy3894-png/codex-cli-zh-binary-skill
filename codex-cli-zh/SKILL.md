---
name: codex-cli-zh
description: One-command source-level Chinese localization and build workflow for OpenAI Codex CLI/TUI. Use when Codex needs codex汉化项目, Codex CLI 汉化项目, Codex CLI 中文汉化, Codex 中文版, 源码汉化, 编译汉化, 汉化版 codex, 中文 codex.exe, Chinese localized Codex, slash-command popup descriptions, approval/auth/trust/startup/model prompts, Windows x64 builds, macOS native builds, Android/Termux musl coordination, wrapper install, untranslated English scans, or reapplying Chinese UI patches after Codex updates.
---

# Codex CLI Chinese Localization

## Purpose

Use this skill for CLI/TUI localization only. It patches the Rust source and rebuilds `codex-cli`; it does not patch Codex Desktop/MSIX and it does not edit CC Switch configuration.

The bundled workflow composes the former slash-command and deep-TUI patch flows into one run:

1. Resolve the installed `codex --version` to `rust-vX.Y.Z`, unless `-RepoRef` is provided.
2. Reuse or sparse-clone `E:\cz\codex-rust-vX.Y.Z`.
3. Apply slash-command translations without building.
4. Apply deeper TUI translations.
5. Build once into a versioned inactive target directory.
6. Optionally make the npm `codex` wrapper start the rebuilt E-drive binary.

## Quick Commands

Plan without changing files:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -DryRun
```

Patch source only:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -SkipBuild
```

Patch and build once:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1"
```

Patch, build, and switch the active npm `codex` command through wrapper override:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -Install -UseWrapperOverride
```

Build a specific upstream CLI ref after npm has updated or before switching:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -RepoRef "rust-v0.142.4" -CargoTargetDir "E:\cz\target-zh-0.142.4"
```

Scan likely visible untranslated English strings:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\scan-codex-cli-zh-coverage.ps1" -SourceRoot "E:\cz\codex-rust-v0.142.4"
```

macOS native build from a terminal with Rust, Git, and Python 3:

```bash
bash "$HOME/.codex/skills/codex-cli-zh/scripts/build-codex-cli-zh-macos.sh" --repo-ref rust-v0.142.4
```

macOS patch-only or install as `~/.local/bin/codex-zh`:

```bash
bash "$HOME/.codex/skills/codex-cli-zh/scripts/build-codex-cli-zh-macos.sh" --repo-ref rust-v0.142.4 --skip-build
bash "$HOME/.codex/skills/codex-cli-zh/scripts/build-codex-cli-zh-macos.sh" --repo-ref rust-v0.142.4 --install
```

## Supported Versions

- Confirmed Windows x64 source builds: Codex CLI `0.142.2` and `0.142.4`.
- Confirmed current PC build and release baseline: Codex CLI `0.142.4`.
- Confirmed Android/Termux-style musl companion build: `0.142.4` for `aarch64-unknown-linux-musl`, through the `codex-android-musl-zh` skill.
- macOS support is source-patch plus native Cargo build support. The script is included for macOS users, but this Windows host cannot runtime-verify a macOS binary.
- Later official tags should be treated as map-compatible only after `-DryRun`, patching, coverage scan, and a real `codex --version` check pass. If upstream strings moved, update the JSON maps first.

## Windows Rules

- Prefer `-UseWrapperOverride` for install. It edits `C:\Users\Administrator\AppData\Roaming\npm\node_modules\@openai\codex\bin\codex.js` so `codex` starts the patched E-drive binary.
- Do not build into the target directory of a currently running `codex.exe`. Windows locks live executables and Cargo can fail at the final replace step. Use an inactive target such as `E:\cz\target-zh-0.142.2` or `E:\cz\target-zh-0.142.2-next`.
- `npm update -g @openai/codex` updates the npm global package and may overwrite the wrapper override. Re-run this skill after npm updates before expecting Chinese UI to remain active.
- Keep old E-drive targets as rollback unless the user explicitly asks to delete them.

## Coverage Workflow

Use the coverage script before and after expanding translations. It reports:

- high-signal visible English sentinels such as model picker, startup help, model descriptions, and status labels;
- bundled slash/deep map counts;
- mapped English strings still present in `tui/src`.

If the scan shows English in `tui/src/chatwidget/model_popups.rs`, `tui/src/history_cell/session.rs`, or model/reasoning description display paths, update the JSON maps or patch logic before rebuilding.

## Verification

Use these checks as evidence:

```powershell
codex --version
& "E:\cz\target-zh-0.142.4\release\codex.exe" --version
rg -n -F "localWindowsBinaryPath" "$env:APPDATA\npm\node_modules\@openai\codex\bin\codex.js"
```

For live UI verification, restart Codex CLI, type `/`, open `/model`, and trigger a permission/auth/trust prompt when possible.
