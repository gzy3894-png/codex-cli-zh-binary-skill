---
name: codex-cli-zh
description: One-command source-level Chinese localization and build workflow for OpenAI Codex CLI/TUI, including configured external model-catalog descriptions. Use when Codex needs codex汉化项目, Codex CLI 汉化项目, Codex CLI 中文汉化, Codex 中文版, 源码汉化, 编译汉化, 汉化版 codex, 中文 codex.exe, Chinese localized Codex, slash-command popup descriptions, approval/auth/trust/startup/model prompts, /model English annotations, model_catalog_json localization, Windows x64 builds, macOS native builds, Android/Termux musl coordination, wrapper install, untranslated English scans, or reapplying Chinese UI patches after Codex updates.
---

# Codex CLI Chinese Localization

## Purpose

Use this skill for CLI/TUI localization only. It patches the Rust source, rebuilds `codex-cli`, and can translate UI descriptions in the configured external `model_catalog_json`. It does not patch Codex Desktop/MSIX and it does not edit CC Switch configuration.

The bundled workflow composes the former slash-command and deep-TUI patch flows into one run:

1. Resolve the installed `codex --version` to `rust-vX.Y.Z`, unless `-RepoRef` is provided.
2. Reuse or sparse-clone `E:\cz\codex-rust-vX.Y.Z`.
3. Apply slash-command translations without building.
4. Apply deeper TUI translations.
5. Optionally translate the configured external model catalog using the same model-description map.
6. Build once into a versioned inactive target directory.
7. Optionally make the npm `codex` wrapper start the rebuilt E-drive binary.

## Quick Commands

Plan without changing files:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -DryRun
```

Plan and apply only the configured external model catalog without rebuilding:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\patch-codex-model-catalog-zh.ps1" -DryRun
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\patch-codex-model-catalog-zh.ps1"
```

Patch source only:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -SkipBuild
```

Patch and build once:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1"
```

Force the conservative build policy on a memory-constrained Windows host:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -LowMemoryBuild -BuildJobs 1
```

Patch, build, and switch the active npm `codex` command through wrapper override:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -Install -UseWrapperOverride -PatchModelCatalog
```

Build a specific upstream CLI ref after npm has updated or before switching:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\apply-codex-cli-zh.ps1" -RepoRef "rust-v0.142.4" -CargoTargetDir "E:\cz\target-zh-0.142.4"
```

Scan likely visible untranslated English strings:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\scan-codex-cli-zh-coverage.ps1" -SourceRoot "E:\cz\codex-rust-v0.142.4"
```

Include the current external model catalog and fail if mapped English UI descriptions remain:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh\scripts\scan-codex-cli-zh-coverage.ps1" -SourceRoot "E:\cz\codex-rust-v0.144.1" -ModelCatalogPath "$env:USERPROFILE\.codex\krill-model-catalog.json" -FailOnFindings
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

- Confirmed Windows x64 source builds: Codex CLI `0.142.2`, `0.142.4`, and `0.144.1`.
- Confirmed current PC build and release baseline: Codex CLI `0.144.1`.
- Confirmed Android/Termux-style musl companion build: `0.142.4` for `aarch64-unknown-linux-musl`, through the `codex-android-musl-zh` skill.
- macOS support is source-patch plus native Cargo build support. The script is included for macOS users, but this Windows host cannot runtime-verify a macOS binary.
- Later official tags should be treated as map-compatible only after `-DryRun`, patching, coverage scan, and a real `codex --version` check pass. If upstream strings moved, update the JSON maps first.

## Windows Rules

- Prefer `-UseWrapperOverride` for install. It edits `C:\Users\Administrator\AppData\Roaming\npm\node_modules\@openai\codex\bin\codex.js` so `codex` starts the patched E-drive binary.
- When `config.toml` sets `model_catalog_json`, add `-PatchModelCatalog` to the combined apply/install command. Pass `-ModelCatalogPath` to override auto-discovery or run `patch-codex-model-catalog-zh.ps1` for a catalog-only repair.
- The catalog patch is exact-value, JSON-validating, idempotent, and backed up under `~/.codex/backups/model-catalog-zh`. Start a new Codex session afterward because the catalog is loaded only at startup.
- The catalog patch resolves the home directory through `USERPROFILE`, `HOME`, or .NET, so explicit and config-discovered catalog paths work under both Windows PowerShell and PowerShell 7 on Linux/macOS runners.
- Do not build into the target directory of a currently running `codex.exe`. Windows locks live executables and Cargo can fail at the final replace step. Use an inactive target such as `E:\cz\target-zh-0.142.2` or `E:\cz\target-zh-0.142.2-next`.
- `npm update -g @openai/codex` updates the npm global package and may overwrite the wrapper override. Re-run this skill after npm updates before expecting Chinese UI to remain active.
- Keep old E-drive targets as rollback unless the user explicitly asks to delete them.
- Refuse to start while another Cargo build is active unless the caller explicitly passes `-AllowConcurrentBuild`.
- On hosts with 24 GiB RAM or less, automatically use one Cargo job and disable release LTO to avoid LLVM allocation failures.
- Run `cargo fmt --all -- --check` before the expensive release build so encoding damage or invalid Rust fails quickly.
- Stream every build line into the timestamped log printed by the script. On failure, report that path rather than relying on stale terminal output.
- Prefer PowerShell 7 for bundled patch scripts. Keep the deep patch script UTF-8 BOM encoded for Windows PowerShell 5.1 fallback compatibility.

## Build Failure Rules

- Never launch a hidden concurrent retry after an out-of-memory failure.
- Preserve the target directory so a deliberate retry can reuse completed artifacts.
- Treat `rustc-LLVM ERROR: out of memory`, `Allocation failed`, and related statuses as resource failures, not translation failures.
- Verify an existing source checkout resolves to the requested Git ref before patching it.
- Verify the built binary version matches `rust-vX.Y.Z` before installation.
- Validate wrapper syntax and CLI startup before keeping an install; restore the timestamped backup on failure.

## Coverage Workflow

Use the coverage script before and after expanding translations. It reports:

- high-signal visible English sentinels such as model picker, startup help, model descriptions, and status labels;
- bundled slash/deep map counts;
- mapped English strings still present in `tui/src` or an explicitly supplied external model catalog.

If the scan shows English in `tui/src/chatwidget/model_popups.rs`, `tui/src/history_cell/session.rs`, or model/reasoning description display paths, update the JSON maps or patch logic before rebuilding.

The `models-manager/models.json` target in `deep-translations.zh.json` is the single source of truth for both bundled and external model-description translations. Keep new model, reasoning-level, and speed-tier phrases there so source builds and `model_catalog_json` stay aligned.

## Verification

Use these checks as evidence:

```powershell
codex --version
& "E:\cz\target-zh-0.144.1\release\codex.exe" --version
rg -n -F "localWindowsBinaryPath" "$env:APPDATA\npm\node_modules\@openai\codex\bin\codex.js"
```

For live UI verification, restart Codex CLI, type `/`, open `/model`, and trigger a permission/auth/trust prompt when possible.
