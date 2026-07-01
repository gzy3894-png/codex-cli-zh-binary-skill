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

## 2026-07-01 Remote Build `4230c10`

- Committed fix as `4230c10 Fix Codex for TUI first-run recovery path`.
- Pushed branch `android-arm64-musl-installer` to GitHub.
- GitHub Actions run `28491354419` completed successfully; artifact name is `codex-for-tui-debug-apk`, artifact ID `7999383674`, uploaded zip size `25455373` bytes, uploaded zip SHA256 `23e4be191a73ef949063aa707a83704d1601c5e9cd9eb5109da103f7ae7cadf9`.
- First local artifact download attempt was interrupted while writing `/workspace/apks/codex-for-tui-4230c10/artifact.zip`; it was incomplete and should not be used.
- Restarting artifact download from run `28491354419` into `/workspace/apks/codex-for-tui-4230c10`.
- `gh run download 28491354419 --name codex-for-tui-debug-apk` failed locally because the HTTPS read connection was aborted before the artifact finished downloading; remote artifact remains valid.
- After the user changed networks, retried with the previous successful `/tmp` download pattern plus a `60s` timeout. Download completed in about `9.5s`.
- Current APK: `/workspace/apks/Codex-for-TUI-debug-4230c10.apk`
- APK sha256: `b09fe6cddd6b34a6d77985a85991745d1e30071d1aac562fd67f289a55559112`
- APK contents verified to include `assets/codex-for-tui-bootstrap.sh`, `assets/install-reterminal-alpine.sh`, `assets/codex-local-resume.sh`, and `assets/init.sh`.

## 2026-07-01 User Test Failure After Environment Check

- User tested `4230c10` APK and reported that after entering `1`, the app printed the `Codex for TUI 环境检查` download plan and then returned to `root@codex-tui` without continuing.
- Reproduced with a local stdin/fake-apk harness: `print_download_plan` ended with `[ -n "$NOTICE_URL" ] && ...`; because `NOTICE_URL` is blank by default and the script runs with `set -e`, the function returned `1` and the installer exited immediately after printing the plan.
- The outer `init.sh` runs `codex-for-tui-bootstrap.sh || true`, so the installer failure was swallowed and appeared as a silent return to shell.
- Fixed `print_download_plan` to return `0` when `NOTICE_URL` is blank.
- Changed `init.sh` to show a warning if bootstrap fails instead of silently swallowing the failure.
- Added isolated smoke tests in `tests/codex-for-tui-installer-smoke.sh` and wired them into GitHub Actions before the APK build. The test extracts pre-main shell functions into a temporary harness, uses temporary HOME/STATE/PATH, fake `apk`, no network, and verifies the first-install prompt plus dependency choice flow.
- Fixed `tty_read` automation behavior so `CODEX_ZH_FORCE_STDIN=1` uses stdin, and non-tty prompts go to stderr rather than contaminating command-substitution output.
- Local verification passed:
  - `timeout 40s sh tests/codex-for-tui-installer-smoke.sh`
  - `timeout 40s sh tests/codex-for-tui-installer-smoke.sh android-app/core/main/src/main/assets/install-reterminal-alpine.sh android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh`
  - `sh -n` for installer/bootstrap/init/resume scripts and test script
  - `git diff --check`
- Committed and pushed as `aac1fbf Fix Codex for TUI installer prompt flow`.
- GitHub Actions run `28492990758` completed successfully. Cloud verification passed `Smoke test installer scripts` before Android build, then produced artifact `codex-for-tui-debug-apk` with artifact ID `7999942097` and uploaded zip size `25455529` bytes.
- Downloaded artifact with a `60s` timeout in `17.3s`.
- Current APK: `/workspace/apks/Codex-for-TUI-debug-aac1fbf.apk`
- APK sha256: `0a2d8846fe31e06a7edf85a012dd8f2b6d5c6f4808a8305b40ddd588384be5e0`
- APK contents verified to include `assets/codex-for-tui-bootstrap.sh`, `assets/install-reterminal-alpine.sh`, `assets/codex-local-resume.sh`, and `assets/init.sh`.
- APK embedded script text verified to include:
  - installer `print_download_plan` returning `0`
  - installer `tty_read` using `tty_available`
  - non-tty prompts writing to stderr
  - bootstrap respecting `CODEX_ZH_FORCE_STDIN`
  - `init.sh` warning on bootstrap failure instead of silently swallowing it

## 2026-07-01 Local Config UX Regression Report

- User tested `aac1fbf` and reported two local configuration UX problems after the Codex archive download finished:
  - The transition into local configuration is not clear enough; the screen is not cleared, so the user has little sense that the flow moved from download/install into local setup.
  - Menu choices are visually too dense, with no blank-line separation; the official-login and third-party-API choices are easy to confuse, and there is no obvious undo/back path.
- Real failure path reported by user:
  - At `请选择要新建的 Codex 配置`, the user pasted `https://api.krill-ai.com/v1` into the menu-number prompt.
  - Current script treats every non-`1` input as third-party mode, so it did not reject the pasted URL.
  - The next prompt read `5` as API Base URL, normalized it to `5/v1`, then attempted to fetch `5/v1/models`, which appeared stuck.
- Required fix:
  - Clear/visually separate local configuration stages.
  - Only accept explicit menu choices.
  - Warn when a URL is pasted into a menu-number prompt.
  - Add back/exit choices where a user can reasonably recover.
  - Validate API Base URL before fetching models.
  - Add isolated shell tests covering the wrong-paste and invalid-URL paths before cloud APK build.

## 2026-07-01 Local Config UX Fix

- Updated `codex-local-resume.sh` and synced the APK asset copy.
- Added stage clear/title output for local setup:
  - `本地配置 1/2：启动提示词`
  - `本地配置 2/2：选择 Codex 配置`
  - `本地配置 2/2：新建 Codex 配置`
  - `本地配置 2/2：第三方 Responses API`
- Reworked menu layout with blank lines between choices.
- Added strict menu validation: invalid text no longer falls through to third-party mode.
- Added a specific warning if a URL is pasted into a menu-number prompt.
- Added exit choices (`q`) and a back choice (`b`) from third-party API input to the config-type menu.
- Added API Base URL validation before model fetching; values like `5` are rejected before any `/models` request.
- Added isolated tests:
  - Pasting `https://api.krill-ai.com/v1` at the config-type menu is rejected with the URL-paste warning.
  - Entering `5` as API Base URL is rejected before `fetch_models` can run.
- Local verification passed:
  - `timeout 40s sh tests/codex-for-tui-installer-smoke.sh`
  - `timeout 40s sh tests/codex-for-tui-installer-smoke.sh android-app/core/main/src/main/assets/install-reterminal-alpine.sh android-app/core/main/src/main/assets/codex-for-tui-bootstrap.sh android-app/core/main/src/main/assets/codex-local-resume.sh`
  - `sh -n` for installer/bootstrap/init/resume scripts and test script
  - `git diff --check`
  - Source and APK asset `codex-local-resume.sh` copies match.
- Committed and pushed as `69b4565 Improve Codex for TUI local config UX`.
- GitHub Actions run `28493681239` completed successfully:
  - Cloud `Smoke test installer scripts` passed.
  - Android debug APK build passed.
- Downloaded artifact with `timeout 60s`; download completed in about 12 seconds.
- Current APK: `/workspace/apks/Codex-for-TUI-debug-69b4565.apk`
- APK sha256: `ee222bac36210376e8848120fe9c8e3192821920ae95049b48d8d09c42ba2dca`
- APK integrity verified with `unzip -t`.
- APK contents verified to include `assets/codex-for-tui-bootstrap.sh`, `assets/codex-local-resume.sh`, `assets/init.sh`, and `assets/install-reterminal-alpine.sh`.
- APK embedded `assets/codex-local-resume.sh` verified to include:
  - URL-paste warning at menu prompts.
  - `API Base URL 格式不对` validation.
  - `输入 b 返回配置类型选择`.
  - `本地配置 2/2：新建 Codex 配置` stage title.
- Note: one first `unzip -p` check was run in parallel with copying the APK into `/workspace/apks` and read the destination before the copy finished, producing a transient zip error. A sequential recheck immediately after confirmed the APK is valid and the source/destination SHA256 values match.

## 2026-07-01 Formal Release `codex-for-tui-v1.0.0`

- Updated the repository README to focus on Codex for TUI in Chinese:
  - Explains what the app is and who it is for.
  - Lists only relevant advantages: Alpine environment, guided install, API/model setup, resume/back/exit flow, terminal-friendly interaction, and Codex command aliases.
  - Adds first-use steps, network notes, repository structure, build/verification notes, upstream attribution, license, and disclaimer.
- Updated `android-app/README.md` to a concise Chinese app-source overview.
- Changed app version name to `1.0.0`; package remains `com.gzy3894.codexfortui`, versionCode remains `10`.
- Changed GitHub Actions Android build from debug APK to release APK:
  - Artifact name: `codex-for-tui-release-apk`
  - Gradle task: `:app:assembleRelease`
  - Release signing uses configured release signing when available, otherwise falls back to the repository testkey so Actions can produce an installable formal package.
- Local script verification passed:
  - `timeout 40s sh tests/codex-for-tui-installer-smoke.sh`
  - `git diff --check`
- Committed and pushed as `d70702f Prepare Codex for TUI release`.
- GitHub Actions run `28494113744` completed successfully:
  - Cloud `Smoke test installer scripts` passed.
  - Android release APK build passed.
- Downloaded release artifact with `timeout 60s`; the artifact download completed, but a follow-up `find -ls` listing failed because BusyBox `find` does not support `-ls`. Rechecked with `ls` and confirmed the downloaded file exists.
- Current formal APK: `/workspace/apks/Codex-for-TUI-1.0.0.apk`
- APK SHA256: `ed24e750df4aa6022ac909927d211c6584b47e7c90fe835e18bd2ae823cb9126`
- APK integrity verified with `unzip -t`.
- APK contents verified to include the bootstrap, installer, local resume, and init scripts.
- APK embedded `assets/codex-local-resume.sh` verified to include the local-config UX fixes from `69b4565`.
- Created GitHub Release:
  - URL: `https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/tag/codex-for-tui-v1.0.0`
  - Tag: `codex-for-tui-v1.0.0`
  - Target commit: `d70702f9c58fbc95490f8c1121e0aadd0d882eb8`
  - Asset: `Codex-for-TUI-1.0.0.apk`
  - Asset size: `22924135` bytes
