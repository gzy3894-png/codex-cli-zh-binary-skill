---
name: codex-android-musl-zh
description: Build a Chinese-localized OpenAI Codex CLI binary for aarch64-unknown-linux-musl from Windows. Use for codex汉化项目, Codex CLI 汉化项目, Codex CLI 中文汉化, Codex 中文版, Android版 Codex, 安卓版 aarch64-unknown-linux-musl, Termux/ARM64 musl Codex builds, cross-compiling Codex, 源码汉化编译, or packaging the Codex Chinese localization build flow as a reusable skill. Always use this skill when a task combines Codex CLI zh localization with ARM64 Linux musl output.
---

# Codex Android Musl Chinese Build

Use this skill to produce a source-localized Codex CLI binary for the
`aarch64-unknown-linux-musl` Rust target from a Windows host.

This skill composes the existing `codex-cli-zh` localization skill instead of
duplicating the translation maps. The output target is a Linux/musl ARM64 ELF
binary. For Android's native Bionic target, use `aarch64-linux-android` and an
Android NDK workflow instead; only use that route when the user explicitly asks
for the Android NDK/Bionic target.

## Quick Command

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-android-musl-zh\scripts\build-codex-android-musl-zh.ps1"
```

The default command:

1. Resolves the installed `codex --version` to `rust-vX.Y.Z`.
2. Reuses or clones the matching Codex source under `E:\cz`.
3. Reapplies `codex-cli-zh` source patches with `-SkipBuild`.
4. Ensures the Rust target `aarch64-unknown-linux-musl` is installed for the
   repo toolchain.
5. Ensures portable Zig and `cargo-zigbuild` exist.
6. Ensures portable Strawberry Perl exists for `gmake` and missing Perl modules,
   then uses Git for Windows' Unix-like Perl with `PERL5LIB` ordered as Git
   Perl's own `/usr/.../perl5` paths first and Strawberry paths second.
   OpenSSL's Linux Configure step rejects Win32 Perl path semantics, while
   putting Strawberry ahead of Git Perl can make Git Perl load incompatible XS
   modules. During the Cargo build, `PERL` is set to `perl` rather than the full
   `C:\Program Files\...` path because OpenSSL writes this value into Makefiles
   that are later executed by MSYS shell. The build also sets
   `MSYS2_ENV_CONV_EXCL=PERL5LIB` so Git/MSYS Perl keeps the colon-separated
   `/usr` and `/e/...` module search path during OpenSSL's `make` phase.
7. Generates stable wrappers under `E:\cz\zigbuild-wrappers` and points target
   `CC`/`CXX`/`AR`/`RANLIB` at forward-slash wrapper paths. `CC`/`CXX` use
   shell-friendly `.cmd` wrappers, while `AR`/`RANLIB` use native `.exe`
   wrappers so long archive argument lists can be passed through response files
   instead of `cmd.exe`.
8. Copies Strawberry `gmake.exe` to `E:\cz\build-tool-wrappers\host\make.exe`
   and puts that directory first on `PATH`, because `openssl-src` invokes
   `make` directly and an MSYS `make` shim can convert `PERL5LIB` into a broken
   Windows semicolon path. The build also sets `MAKEFLAGS=-jN` with a bounded
   host CPU count so vendored OpenSSL does not sit in a long single-threaded C
   build, and sets `PYTHON` to the configured Python executable for `rusty_v8`
   downloads.
9. For `aarch64-unknown-linux-musl`, patches `codex-code-mode` into a protocol
   compatible stub, neutralizes the code-mode `sandbox` feature's direct `v8`
   feature link, and moves the `v8`/`deno_core_icudata` dependencies behind a
   non-musl target cfg, then refreshes `Cargo.lock` before the locked build.
   This avoids the missing upstream
   `librusty_v8_release_aarch64-unknown-linux-musl.a.gz` release artifact; code
   mode will report unavailable in this musl build.
10. Builds `codex-cli` with:

```powershell
cargo-zigbuild zigbuild -p codex-cli --bin codex --release --target aarch64-unknown-linux-musl --locked
```

11. Copies the final binary to
    `E:\cz\dist\codex-<version>-zh-aarch64-unknown-linux-musl`, then strips
    debug/symbol sections with Rust's `llvm-strip` by default. Pass
    `-KeepDebugInfo` if an unstripped diagnostic artifact is needed.

## Useful Options

Build a specific upstream ref:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-android-musl-zh\scripts\build-codex-android-musl-zh.ps1" -RepoRef "rust-v0.142.2"
```

Use an existing source checkout:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-android-musl-zh\scripts\build-codex-android-musl-zh.ps1" -SourceRoot "E:\cz\codex-rust-v0.142.2"
```

Skip downloading/building prerequisite tools and fail if they are missing:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-android-musl-zh\scripts\build-codex-android-musl-zh.ps1" -SkipPrereqInstall
```

Create a `.tar.gz` next to the copied binary:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-android-musl-zh\scripts\build-codex-android-musl-zh.ps1" -PackageTarGz
```

## Supported Versions

- Verified artifact baseline: Codex CLI `0.142.4` for `aarch64-unknown-linux-musl`.
- The shared source-localization maps have also been verified for Windows x64 Codex CLI `0.142.2` and `0.142.4`.
- For later official `rust-vX.Y.Z` tags, run the patch/coverage workflow first and treat missing English strings as an upstream wording change that needs a JSON map update.
- This target is Linux/musl ARM64. It is useful for Android/Termux-like musl environments but is not the Android NDK/Bionic `aarch64-linux-android` target.

## Defaults

- Work root: `E:\cz`
- Source root: `E:\cz\codex-rust-v<version>`
- Cargo home: `E:\cz\cargo-home`
- Cargo target dir: `E:\cz\target-zh-<version>-aarch64-musl`
- Cargo tools root: `E:\cz\cargo-tools`
- Zig: `E:\tools\zig\0.16.0\zig-x86_64-windows-0.16.0\zig.exe`
- Strawberry Perl/module and gmake root:
  `E:\tools\strawberry-perl-5.42.2.1-64bit-portable`
- Unix-like Perl: `C:\Program Files\Git\usr\bin\perl.exe`
- Dist dir: `E:\cz\dist`

## Verification

Because the output is an ARM64 Linux ELF binary, do not try to run it on
Windows. Verify locally with file metadata and hashes, then verify on device:

```powershell
Get-Item "E:\cz\dist\codex-0.142.2-zh-aarch64-unknown-linux-musl"
Get-FileHash "E:\cz\dist\codex-0.142.2-zh-aarch64-unknown-linux-musl" -Algorithm SHA256
```

On the target device or Linux environment:

```bash
chmod +x ./codex-0.142.2-zh-aarch64-unknown-linux-musl
./codex-0.142.2-zh-aarch64-unknown-linux-musl --version
```

## Notes

- Keep old `E:\cz\target-*` directories as build caches and rollback points
  unless the user asks to delete them.
- If antivirus blocks Cargo build scripts with Windows `os error 5`, disable
  that interception and retry. Prefer a fresh `-CargoTargetDir` if the previous
  target dir produced partial `openssl-sys` metadata after an interrupted run.
- The build script prints SHA256 with `Get-FileHash` when available and falls
  back to `certutil.exe` on stripped-down Windows PowerShell environments.
- The default dist artifact is stripped to keep Android transfer size
  reasonable; the Cargo target directory still keeps the unstripped build
  output.
- `rusty_v8` does not publish a prebuilt static archive for
  `aarch64-unknown-linux-musl` at least for `v8` crate `149.2.0`; the skill
  therefore disables the code-mode runtime for this target instead of trying a
  multi-hour V8 source build from Windows.
- If `cargo-zigbuild` fails in vendored OpenSSL, SQLite, `ring`, or `zstd-sys`,
  preserve the full stderr log and adjust only the target-specific C compiler or
  Zig settings.
- Do not install the musl binary into the Windows npm `codex` wrapper; it cannot
  run on Windows.
