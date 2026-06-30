[CmdletBinding()]
param(
    [string]$SourceRoot = "",
    [string]$RepoRef = "",
    [string]$RepoUrl = "https://github.com/openai/codex.git",
    [string]$WorkRoot = "E:\cz",
    [string]$CargoHome = "E:\cz\cargo-home",
    [string]$CargoTargetDir = "",
    [string]$CargoToolsRoot = "E:\cz\cargo-tools",
    [string]$Target = "aarch64-unknown-linux-musl",
    [string]$ZigDir = "E:\tools\zig\0.16.0\zig-x86_64-windows-0.16.0",
    [string]$StrawberryPerlRoot = "E:\tools\strawberry-perl-5.42.2.1-64bit-portable",
    [string]$UnixPerlExe = "C:\Program Files\Git\usr\bin\perl.exe",
    [string]$DistDir = "",
    [string]$PythonExe = "E:\tools\python\python.exe",
    [string]$CodexZhSkillRoot = "",
    [switch]$SkipPatch,
    [switch]$SkipPrereqInstall,
    [switch]$KeepDebugInfo,
    [switch]$PackageTarGz
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ZigVersion = "0.16.0"
$ZigUrl = "https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip"
$ZigSha256 = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"
$StrawberryPerlVersion = "5.42.2.1"
$StrawberryPerlUrl = "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54221_64bit/strawberry-perl-5.42.2.1-64bit-portable.zip"
$StrawberryPerlSha256 = "32d83be90cf04b807cfb9477482bc36302cdee6f5b04cf57e81adecbd8f07898"

function Write-Step {
    param([string]$Name)
    Write-Host ""
    Write-Host "== $Name =="
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory = ""
    )

    $oldLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $WorkingDirectory
        }
        Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join " "))
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
        }
    }
    finally {
        Set-Location $oldLocation
    }
}

function Get-Sha256Hex {
    param([string]$Path)

    $getFileHash = Get-Command -Name "Get-FileHash" -ErrorAction SilentlyContinue
    if ($getFileHash) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $certutil = Get-Command -Name "certutil.exe" -ErrorAction SilentlyContinue
    if (-not $certutil) {
        throw "Neither Get-FileHash nor certutil.exe is available to compute SHA256."
    }

    $output = & certutil.exe -hashfile $Path SHA256
    if ($LASTEXITCODE -ne 0) {
        throw "certutil.exe failed to compute SHA256 for $Path"
    }

    $hashLine = $output | Where-Object { $_ -match "^[0-9A-Fa-f]{64}$" } | Select-Object -First 1
    if (-not $hashLine) {
        throw "Unable to parse SHA256 from certutil.exe output for $Path"
    }

    return $hashLine.ToLowerInvariant()
}

function Find-LlvmStrip {
    param([string]$Toolchain)

    $rustupArgs = @()
    if ($Toolchain) {
        $rustupArgs += "+$Toolchain"
    }

    $rustcPath = & "rustup" @rustupArgs "which" "rustc" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $rustcPath) {
        return ""
    }

    $toolchainRoot = Split-Path -Parent (Split-Path -Parent $rustcPath)
    $rustlibDir = Join-Path $toolchainRoot "lib\rustlib"
    if (-not (Test-Path -LiteralPath $rustlibDir)) {
        return ""
    }

    $match = Get-ChildItem -LiteralPath $rustlibDir -Recurse -Filter "llvm-strip.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($match) {
        return $match.FullName
    }

    return ""
}

function Ensure-LlvmStrip {
    param(
        [string]$Toolchain,
        [switch]$NoInstall
    )

    $llvmStrip = Find-LlvmStrip -Toolchain $Toolchain
    if ($llvmStrip) {
        return $llvmStrip
    }

    if ($NoInstall) {
        return ""
    }

    Write-Step "Install llvm-tools"
    $args = @()
    if ($Toolchain) {
        $args += "+$Toolchain"
    }
    $args += @("component", "add", "llvm-tools-preview")
    Invoke-Checked -FilePath "rustup" -Arguments $args

    return Find-LlvmStrip -Toolchain $Toolchain
}

function ConvertTo-MsysPath {
    param([string]$Path)

    $fullPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ($fullPath -match "^([A-Za-z]):\\(.*)$") {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace "\\", "/"
        return "/$drive/$rest"
    }
    return ($fullPath -replace "\\", "/")
}

function Get-CodexVersion {
    try {
        $output = & codex --version 2>$null
        if ($output -match "codex-cli\s+([0-9]+\.[0-9]+\.[0-9]+)") {
            return $Matches[1]
        }
    }
    catch {
        return ""
    }
    return ""
}

function Get-VersionLabel {
    param(
        [string]$Version,
        [string]$Ref
    )

    if ($Ref -match "^rust-v(.+)$") {
        return $Matches[1]
    }
    if ($Version) {
        return $Version
    }
    return ($Ref -replace "[^A-Za-z0-9._-]", "-")
}

function Resolve-CodexZhSkillRoot {
    param([string]$Requested)

    if ($Requested) {
        $resolved = (Resolve-Path -LiteralPath $Requested -ErrorAction Stop).Path
        if (Test-Path -LiteralPath (Join-Path $resolved "scripts\apply-codex-cli-zh.ps1")) {
            return $resolved
        }
        throw "codex-cli-zh apply script was not found under: $resolved"
    }

    $skillDir = Split-Path -Parent $PSScriptRoot
    $skillsRoot = Split-Path -Parent $skillDir
    $candidates = @(
        (Join-Path $skillsRoot "codex-cli-zh"),
        (Join-Path $env:USERPROFILE ".codex\skills\codex-cli-zh"),
        "E:\relocated-from-c\.codex\skills\codex-cli-zh"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "scripts\apply-codex-cli-zh.ps1")) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }

    throw "Could not find codex-cli-zh skill. Pass -CodexZhSkillRoot."
}

function Get-PlannedSourceRoot {
    param(
        [string]$RequestedSourceRoot,
        [string]$Root,
        [string]$Ref
    )

    if ($RequestedSourceRoot) {
        return (Resolve-Path -LiteralPath $RequestedSourceRoot -ErrorAction Stop).Path
    }

    $safeRef = $Ref -replace "[^A-Za-z0-9._-]", "-"
    return (Join-Path $Root ("codex-" + $safeRef))
}

function Get-RepoToolchain {
    param([string]$CargoRoot)

    $toolchainFile = Join-Path $CargoRoot "rust-toolchain.toml"
    if (-not (Test-Path -LiteralPath $toolchainFile)) {
        return ""
    }

    $content = Get-Content -LiteralPath $toolchainFile -Raw
    if ($content -match 'channel\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }
    return ""
}

function Ensure-RustTarget {
    param(
        [string]$Toolchain,
        [string]$RustTarget
    )

    Write-Step "Ensure Rust target"
    if ($Toolchain) {
        Invoke-Checked -FilePath "rustup" -Arguments @("+$Toolchain", "target", "add", $RustTarget)
    }
    else {
        Invoke-Checked -FilePath "rustup" -Arguments @("target", "add", $RustTarget)
    }
}

function Ensure-Zig {
    param(
        [string]$Directory,
        [switch]$NoInstall
    )

    $zigExe = Join-Path $Directory "zig.exe"
    if (Test-Path -LiteralPath $zigExe) {
        return (Resolve-Path -LiteralPath $zigExe -ErrorAction Stop).Path
    }

    if ($NoInstall) {
        throw "zig.exe not found at $zigExe and -SkipPrereqInstall was set."
    }

    Write-Step "Install portable Zig"
    $archiveDir = Split-Path -Parent (Split-Path -Parent $Directory)
    $archive = Join-Path $archiveDir "zig-x86_64-windows-$ZigVersion.zip"
    New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null

    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-Checked -FilePath "curl.exe" -Arguments @("-L", "-o", $archive, $ZigUrl)
    }

    $actual = Get-Sha256Hex -Path $archive
    if ($actual -ne $ZigSha256) {
        throw "Zig SHA256 mismatch. Expected $ZigSha256 but got $actual"
    }

    $extractRoot = Split-Path -Parent $Directory
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force

    if (-not (Test-Path -LiteralPath $zigExe)) {
        throw "zig.exe was not found after extraction: $zigExe"
    }
    return (Resolve-Path -LiteralPath $zigExe -ErrorAction Stop).Path
}

function Ensure-CargoZigbuild {
    param(
        [string]$ToolsRoot,
        [switch]$NoInstall
    )

    $exe = Join-Path $ToolsRoot "bin\cargo-zigbuild.exe"
    if (Test-Path -LiteralPath $exe) {
        return (Resolve-Path -LiteralPath $exe -ErrorAction Stop).Path
    }

    if ($NoInstall) {
        throw "cargo-zigbuild.exe not found at $exe and -SkipPrereqInstall was set."
    }

    Write-Step "Install cargo-zigbuild"
    Invoke-Checked -FilePath "cargo" -Arguments @("install", "cargo-zigbuild", "--locked", "--root", $ToolsRoot)
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "cargo-zigbuild.exe was not installed at $exe"
    }
    return (Resolve-Path -LiteralPath $exe -ErrorAction Stop).Path
}

function Ensure-StrawberryPerl {
    param(
        [string]$Root,
        [switch]$NoInstall
    )

    $perlExe = Join-Path $Root "perl\bin\perl.exe"
    $gmakeExe = Join-Path $Root "c\bin\gmake.exe"
    if ((Test-Path -LiteralPath $perlExe) -and (Test-Path -LiteralPath $gmakeExe)) {
        $resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
        return [pscustomobject]@{
            Root = $resolvedRoot
            PerlExe = (Resolve-Path -LiteralPath $perlExe -ErrorAction Stop).Path
            GmakeExe = (Resolve-Path -LiteralPath $gmakeExe -ErrorAction Stop).Path
            PerlBin = Join-Path $resolvedRoot "perl\bin"
            CBin = Join-Path $resolvedRoot "c\bin"
            PerlLib = Join-Path $resolvedRoot "perl\lib"
            PerlVendorLib = Join-Path $resolvedRoot "perl\vendor\lib"
            PerlSiteLib = Join-Path $resolvedRoot "perl\site\lib"
        }
    }

    if ($NoInstall) {
        throw "Strawberry Perl not found at $Root and -SkipPrereqInstall was set."
    }

    Write-Step "Install portable Strawberry Perl"
    $downloadDir = Join-Path (Split-Path -Parent $Root) "downloads"
    $archive = Join-Path $downloadDir "strawberry-perl-$StrawberryPerlVersion-64bit-portable.zip"
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-Checked -FilePath "curl.exe" -Arguments @("-L", "-o", $archive, $StrawberryPerlUrl)
    }

    $actual = Get-Sha256Hex -Path $archive
    if ($actual -ne $StrawberryPerlSha256) {
        throw "Strawberry Perl SHA256 mismatch. Expected $StrawberryPerlSha256 but got $actual"
    }

    $extractRoot = Split-Path -Parent $Root
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force

    if (-not ((Test-Path -LiteralPath $perlExe) -and (Test-Path -LiteralPath $gmakeExe))) {
        throw "Strawberry Perl tools were not found after extraction under: $Root"
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
    return [pscustomobject]@{
        Root = $resolvedRoot
        PerlExe = (Resolve-Path -LiteralPath $perlExe -ErrorAction Stop).Path
        GmakeExe = (Resolve-Path -LiteralPath $gmakeExe -ErrorAction Stop).Path
        PerlBin = Join-Path $resolvedRoot "perl\bin"
        CBin = Join-Path $resolvedRoot "c\bin"
        PerlLib = Join-Path $resolvedRoot "perl\lib"
        PerlVendorLib = Join-Path $resolvedRoot "perl\vendor\lib"
        PerlSiteLib = Join-Path $resolvedRoot "perl\site\lib"
    }
}

function Ensure-UnixLikePerl {
    param(
        [string]$PerlExe,
        [object]$Strawberry
    )

    if (-not (Test-Path -LiteralPath $PerlExe)) {
        throw "Unix-like Perl was not found: $PerlExe. Install Git for Windows or pass -UnixPerlExe."
    }

    $resolvedPerl = (Resolve-Path -LiteralPath $PerlExe -ErrorAction Stop).Path
    $oldDiscoveryPerl5Lib = $env:PERL5LIB
    try {
        $env:PERL5LIB = $null
        $gitIncText = & $resolvedPerl -e "print join(q{:}, grep { m{^/usr/} } @INC)"
        if ($LASTEXITCODE -ne 0) {
            throw "Unix-like Perl could not report its default \@INC."
        }
    }
    finally {
        $env:PERL5LIB = $oldDiscoveryPerl5Lib
    }

    $strawberryLibs = @(
        (ConvertTo-MsysPath -Path $Strawberry.PerlLib),
        (ConvertTo-MsysPath -Path $Strawberry.PerlVendorLib),
        (ConvertTo-MsysPath -Path $Strawberry.PerlSiteLib)
    )
    $perl5Entries = @()
    foreach ($entry in (($gitIncText -split ":") + $strawberryLibs)) {
        if ($entry -and ($perl5Entries -notcontains $entry)) {
            $perl5Entries += $entry
        }
    }
    $perl5Lib = $perl5Entries -join ":"

    $oldPerl5Lib = $env:PERL5LIB
    try {
        $env:PERL5LIB = $perl5Lib
        & $resolvedPerl -MFindBin -MCwd -MExtUtils::MakeMaker -MPod::Usage -MLocale::Maketext::Simple -e "print qq(unix perl ok\n)" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Unix-like Perl could not load OpenSSL Configure Perl modules via PERL5LIB."
        }
    }
    finally {
        $env:PERL5LIB = $oldPerl5Lib
    }

    return [pscustomobject]@{
        PerlExe = $resolvedPerl
        PerlBin = Split-Path -Parent $resolvedPerl
        Perl5Lib = $perl5Lib
    }
}

function Resolve-CSharpCompiler {
    $candidates = @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v3.5\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v3.5\csc.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }

    throw "Could not find csc.exe for native AR/RANLIB wrapper generation."
}

function New-ZigNativeToolWrapper {
    param([string]$OutputPath)

    $sourcePath = [System.IO.Path]::ChangeExtension($OutputPath, ".cs")
    $source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class Program
{
    static int Main(string[] args)
    {
        string zig = Environment.GetEnvironmentVariable("CODEX_ZIGWRAP_ZIG_PATH");
        if (String.IsNullOrEmpty(zig))
        {
            Console.Error.WriteLine("CODEX_ZIGWRAP_ZIG_PATH is not set.");
            return 2;
        }

        string name = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]).ToLowerInvariant();
        if (name.IndexOf("ranlib", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return RunZig(zig, BuildCommand("ranlib", args));
        }
        if (name.IndexOf("ar", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return RunArWithResponseFile(zig, args);
        }

        Console.Error.WriteLine("Unknown zig wrapper mode for executable name: " + name);
        return 2;
    }

    static int RunArWithResponseFile(string zig, string[] args)
    {
        string rsp = Path.Combine(Path.GetTempPath(), "codex-zig-ar-" + Process.GetCurrentProcess().Id + "-" + Guid.NewGuid().ToString("N") + ".rsp");
        string[] lines = new string[args.Length];
        for (int i = 0; i < args.Length; i++)
        {
            lines[i] = QuoteResponseArg(args[i]);
        }

        File.WriteAllLines(rsp, lines, new UTF8Encoding(false));
        try
        {
            return RunZig(zig, "ar " + QuoteCommandArg("@" + rsp));
        }
        finally
        {
            try { File.Delete(rsp); } catch { }
        }
    }

    static string BuildCommand(string tool, string[] args)
    {
        StringBuilder builder = new StringBuilder(tool);
        for (int i = 0; i < args.Length; i++)
        {
            builder.Append(' ');
            builder.Append(QuoteCommandArg(args[i]));
        }
        return builder.ToString();
    }

    static int RunZig(string zig, string arguments)
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = zig;
        psi.Arguments = arguments;
        psi.UseShellExecute = false;

        using (Process process = Process.Start(psi))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    static string QuoteCommandArg(string arg)
    {
        if (arg.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = false;
        for (int i = 0; i < arg.Length; i++)
        {
            char ch = arg[i];
            if (Char.IsWhiteSpace(ch) || ch == '"')
            {
                needsQuotes = true;
                break;
            }
        }
        if (!needsQuotes)
        {
            return arg;
        }

        StringBuilder builder = new StringBuilder();
        builder.Append('"');
        int backslashes = 0;
        for (int i = 0; i < arg.Length; i++)
        {
            char ch = arg[i];
            if (ch == '\\')
            {
                backslashes++;
                continue;
            }
            if (ch == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
                builder.Append('"');
                backslashes = 0;
                continue;
            }
            builder.Append('\\', backslashes);
            backslashes = 0;
            builder.Append(ch);
        }
        builder.Append('\\', backslashes * 2);
        builder.Append('"');
        return builder.ToString();
    }

    static string QuoteResponseArg(string arg)
    {
        return QuoteCommandArg(arg);
    }
}
'@

    Set-Content -LiteralPath $sourcePath -Encoding ASCII -Value $source
    $csc = Resolve-CSharpCompiler
    Invoke-Checked -FilePath $csc -Arguments @("/nologo", "/target:exe", "/out:$OutputPath", $sourcePath)

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "Native zig wrapper was not generated: $OutputPath"
    }
}

function New-HostBuildToolWrappers {
    param(
        [string]$WrapperRoot,
        [string]$GmakeExe
    )

    $hostWrapperDir = Join-Path $WrapperRoot "host"
    New-Item -ItemType Directory -Force -Path $hostWrapperDir | Out-Null

    $makeExe = Join-Path $hostWrapperDir "make.exe"
    Copy-Item -LiteralPath $GmakeExe -Destination $makeExe -Force

    return [pscustomobject]@{
        BinDir = (Resolve-Path -LiteralPath $hostWrapperDir -ErrorAction Stop).Path
        MakeExe = (Resolve-Path -LiteralPath $makeExe -ErrorAction Stop).Path
    }
}

function New-ZigbuildTargetToolWrappers {
    param(
        [string]$WrapperRoot,
        [string]$RustTarget,
        [string]$ZigTarget,
        [string]$CargoZigbuildExe,
        [string]$ZigExe
    )

    $targetWrapperDir = Join-Path $WrapperRoot $RustTarget
    New-Item -ItemType Directory -Force -Path $targetWrapperDir | Out-Null

    $resolvedCargoZigbuild = (Resolve-Path -LiteralPath $CargoZigbuildExe -ErrorAction Stop).Path
    $resolvedZig = (Resolve-Path -LiteralPath $ZigExe -ErrorAction Stop).Path
    $safeZigTarget = $ZigTarget -replace "[^A-Za-z0-9._-]", "-"

    $nativeWrapper = Join-Path $targetWrapperDir "zigtool-wrapper.exe"
    New-ZigNativeToolWrapper -OutputPath $nativeWrapper

    $definitions = @(
        @{
            Key = "CC"
            Name = "zigcc-$safeZigTarget.cmd"
            Args = "zig cc -- -g -fno-sanitize=all -target $ZigTarget %*"
        },
        @{
            Key = "CXX"
            Name = "zigcxx-$safeZigTarget.cmd"
            Args = "zig c++ -- -g -fno-sanitize=all -target $ZigTarget %*"
        },
        @{
            Key = "AR"
            Name = "zigar.exe"
            Native = $true
        },
        @{
            Key = "RANLIB"
            Name = "zigranlib.exe"
            Native = $true
        }
    )

    $result = [ordered]@{}
    foreach ($definition in $definitions) {
        $path = Join-Path $targetWrapperDir $definition.Name
        if ($definition.ContainsKey("Native") -and $definition.Native) {
            Copy-Item -LiteralPath $nativeWrapper -Destination $path -Force
        }
        else {
            $body = @(
                "@echo off",
                "setlocal DisableDelayedExpansion",
                "set ""CARGO_ZIGBUILD_ZIG_PATH=$resolvedZig""",
                """$resolvedCargoZigbuild"" $($definition.Args)"
            )
            Set-Content -LiteralPath $path -Encoding ASCII -Value ($body -join "`r`n")
        }
        $result[$definition.Key] = ((Resolve-Path -LiteralPath $path -ErrorAction Stop).Path -replace "\\", "/")
    }

    return [pscustomobject]$result
}

function Apply-CodeModeMuslStub {
    param(
        [string]$CargoRoot,
        [string]$RustTarget
    )

    if ($RustTarget -ne "aarch64-unknown-linux-musl") {
        return
    }

    Write-Step "Patch code-mode V8 stub"
    $codeModeRoot = Join-Path $CargoRoot "code-mode"
    $codeModeToml = Join-Path $codeModeRoot "Cargo.toml"
    $libRs = Join-Path $codeModeRoot "src\lib.rs"
    $stubRs = Join-Path $codeModeRoot "src\service_stub.rs"

    if (-not (Test-Path -LiteralPath $codeModeToml)) {
        throw "codex-code-mode Cargo.toml was not found: $codeModeToml"
    }
    if (-not (Test-Path -LiteralPath $libRs)) {
        throw "codex-code-mode lib.rs was not found: $libRs"
    }

    $toml = Get-Content -LiteralPath $codeModeToml -Raw
    $updatedToml = [regex]::Replace($toml, '(?m)^\s*sandbox\s*=\s*\["v8/v8_enable_sandbox"\]\r?\n', "sandbox = []`r`n")
    $updatedToml = [regex]::Replace($updatedToml, "(?m)^\s*deno_core_icudata\s*=\s*\{\s*workspace\s*=\s*true\s*\}\r?\n", "")
    $updatedToml = [regex]::Replace($updatedToml, "(?m)^\s*v8\s*=\s*\{\s*workspace\s*=\s*true\s*\}\r?\n", "")
    $targetHeader = '[target.''cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))''.dependencies]'
    if ($updatedToml -notlike "*$targetHeader*") {
        $updatedToml = $updatedToml.TrimEnd() + "`r`n`r`n$targetHeader`r`ndeno_core_icudata = { workspace = true }`r`nv8 = { workspace = true }`r`n"
    }
    if ($updatedToml -ne $toml) {
        Set-Content -LiteralPath $codeModeToml -Encoding ASCII -Value $updatedToml
    }

    $libSource = @'
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
mod cell_actor;
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
mod runtime;
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
mod service;
#[cfg(all(target_arch = "aarch64", target_os = "linux", target_env = "musl"))]
mod service_stub;
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
mod session_runtime;

pub use codex_code_mode_protocol::*;
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
pub use service::CodeModeService;
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
pub use service::InProcessCodeModeSessionProvider;
#[cfg(not(all(target_arch = "aarch64", target_os = "linux", target_env = "musl")))]
pub use service::NoopCodeModeSessionDelegate;
#[cfg(all(target_arch = "aarch64", target_os = "linux", target_env = "musl"))]
pub use service_stub::CodeModeService;
#[cfg(all(target_arch = "aarch64", target_os = "linux", target_env = "musl"))]
pub use service_stub::InProcessCodeModeSessionProvider;
#[cfg(all(target_arch = "aarch64", target_os = "linux", target_env = "musl"))]
pub use service_stub::NoopCodeModeSessionDelegate;
'@
    $currentLib = Get-Content -LiteralPath $libRs -Raw
    if ($currentLib -ne $libSource) {
        Set-Content -LiteralPath $libRs -Encoding ASCII -Value $libSource
    }

    $stubSource = @'
use std::sync::Arc;

use codex_code_mode_protocol::CellId;
use codex_code_mode_protocol::CodeModeNestedToolCall;
use codex_code_mode_protocol::CodeModeSession;
use codex_code_mode_protocol::CodeModeSessionDelegate;
use codex_code_mode_protocol::CodeModeSessionProvider;
use codex_code_mode_protocol::CodeModeSessionProviderFuture;
use codex_code_mode_protocol::CodeModeSessionResultFuture;
use codex_code_mode_protocol::ExecuteRequest;
use codex_code_mode_protocol::ExecuteToPendingOutcome;
use codex_code_mode_protocol::NotificationFuture;
use codex_code_mode_protocol::RuntimeResponse;
use codex_code_mode_protocol::StartedCell;
use codex_code_mode_protocol::ToolInvocationFuture;
use codex_code_mode_protocol::WaitOutcome;
use codex_code_mode_protocol::WaitRequest;
use codex_code_mode_protocol::WaitToPendingOutcome;
use codex_code_mode_protocol::WaitToPendingRequest;
use tokio_util::sync::CancellationToken;

const UNSUPPORTED: &str =
    "code mode is unavailable in this aarch64-unknown-linux-musl build";

pub struct NoopCodeModeSessionDelegate;

impl CodeModeSessionDelegate for NoopCodeModeSessionDelegate {
    fn invoke_tool<'a>(
        &'a self,
        _invocation: CodeModeNestedToolCall,
        cancellation_token: CancellationToken,
    ) -> ToolInvocationFuture<'a> {
        Box::pin(async move {
            cancellation_token.cancelled().await;
            Err("code mode nested tools are unavailable".to_string())
        })
    }

    fn notify<'a>(
        &'a self,
        _call_id: String,
        _cell_id: CellId,
        _text: String,
        _cancellation_token: CancellationToken,
    ) -> NotificationFuture<'a> {
        Box::pin(async { Ok(()) })
    }

    fn cell_closed(&self, _cell_id: &CellId) {}
}

#[derive(Default)]
pub struct InProcessCodeModeSessionProvider;

impl CodeModeSessionProvider for InProcessCodeModeSessionProvider {
    fn create_session<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
    ) -> CodeModeSessionProviderFuture<'a> {
        Box::pin(async move {
            let session: Arc<dyn CodeModeSession> =
                Arc::new(CodeModeService::with_delegate(delegate));
            Ok(session)
        })
    }
}

pub struct CodeModeService;

impl CodeModeService {
    pub fn new() -> Self {
        Self::with_delegate(Arc::new(NoopCodeModeSessionDelegate))
    }

    pub fn with_delegate(_delegate: Arc<dyn CodeModeSessionDelegate>) -> Self {
        Self
    }

    pub async fn execute(&self, _request: ExecuteRequest) -> Result<StartedCell, String> {
        Err(UNSUPPORTED.to_string())
    }

    pub async fn execute_to_pending(
        &self,
        _request: ExecuteRequest,
    ) -> Result<ExecuteToPendingOutcome, String> {
        Err(UNSUPPORTED.to_string())
    }

    pub async fn wait(&self, request: WaitRequest) -> Result<WaitOutcome, String> {
        Ok(WaitOutcome::MissingCell(missing_cell_response(
            request.cell_id,
        )))
    }

    pub async fn terminate(&self, cell_id: CellId) -> Result<WaitOutcome, String> {
        Ok(WaitOutcome::MissingCell(missing_cell_response(cell_id)))
    }

    pub async fn wait_to_pending(
        &self,
        request: WaitToPendingRequest,
    ) -> Result<WaitToPendingOutcome, String> {
        Ok(WaitToPendingOutcome::MissingCell(missing_cell_response(
            request.cell_id,
        )))
    }

    pub async fn shutdown(&self) -> Result<(), String> {
        Ok(())
    }
}

impl Default for CodeModeService {
    fn default() -> Self {
        Self::new()
    }
}

impl CodeModeSession for CodeModeService {
    fn is_alive(&self) -> bool {
        false
    }

    fn execute<'a>(
        &'a self,
        request: ExecuteRequest,
    ) -> CodeModeSessionResultFuture<'a, StartedCell> {
        Box::pin(CodeModeService::execute(self, request))
    }

    fn wait<'a>(&'a self, request: WaitRequest) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(CodeModeService::wait(self, request))
    }

    fn terminate<'a>(&'a self, cell_id: CellId) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(CodeModeService::terminate(self, cell_id))
    }

    fn shutdown<'a>(&'a self) -> CodeModeSessionResultFuture<'a, ()> {
        Box::pin(CodeModeService::shutdown(self))
    }
}

fn missing_cell_response(cell_id: CellId) -> RuntimeResponse {
    RuntimeResponse::Result {
        cell_id,
        content_items: Vec::new(),
        error_text: Some(UNSUPPORTED.to_string()),
    }
}
'@
    $currentStub = if (Test-Path -LiteralPath $stubRs) { Get-Content -LiteralPath $stubRs -Raw } else { "" }
    if ($currentStub -ne $stubSource) {
        Set-Content -LiteralPath $stubRs -Encoding ASCII -Value $stubSource
    }
}

function Update-CargoLockfile {
    param(
        [string]$CargoRoot,
        [string]$CargoHomePath
    )

    Write-Step "Refresh Cargo lockfile"
    New-Item -ItemType Directory -Force -Path $CargoHomePath | Out-Null
    $oldCargoHomeForLock = $env:CARGO_HOME
    $oldLocationForLock = Get-Location
    try {
        Set-Location -LiteralPath $CargoRoot
        $env:CARGO_HOME = $CargoHomePath
        Write-Host "> cargo metadata --format-version 1"
        & cargo "metadata" "--format-version" "1" 1>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: cargo metadata"
        }
    }
    finally {
        Set-Location $oldLocationForLock
        $env:CARGO_HOME = $oldCargoHomeForLock
    }
}

$version = Get-CodexVersion
if (-not $RepoRef) {
    if ($version) {
        $RepoRef = "rust-v$version"
    }
    else {
        $RepoRef = "main"
    }
}

$versionLabel = Get-VersionLabel -Version $version -Ref $RepoRef
if (-not $CargoTargetDir) {
    $CargoTargetDir = Join-Path $WorkRoot ("target-zh-" + $versionLabel + "-aarch64-musl")
}
if (-not $DistDir) {
    $DistDir = Join-Path $WorkRoot "dist"
}

$codexZhRoot = Resolve-CodexZhSkillRoot -Requested $CodexZhSkillRoot
$applyZh = Join-Path $codexZhRoot "scripts\apply-codex-cli-zh.ps1"
$sourcePath = Get-PlannedSourceRoot -RequestedSourceRoot $SourceRoot -Root $WorkRoot -Ref $RepoRef

Write-Step "Plan"
Write-Host "Codex version:       $(if ($version) { $version } else { 'unknown' })"
Write-Host "Repo ref:            $RepoRef"
Write-Host "Target:              $Target"
Write-Host "Work root:           $WorkRoot"
Write-Host "Source root:         $sourcePath"
Write-Host "Cargo home:          $CargoHome"
Write-Host "Cargo target dir:    $CargoTargetDir"
Write-Host "Cargo tools root:    $CargoToolsRoot"
Write-Host "Zig dir:             $ZigDir"
Write-Host "Strawberry Perl:     $StrawberryPerlRoot"
Write-Host "Unix-like Perl:      $UnixPerlExe"
Write-Host "Dist dir:            $DistDir"
Write-Host "codex-cli-zh skill:  $codexZhRoot"

if (-not $SkipPatch) {
    Write-Step "Apply Chinese source patches"
    Invoke-Checked -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $applyZh,
        "-SourceRoot",
        $sourcePath,
        "-RepoRef",
        $RepoRef,
        "-RepoUrl",
        $RepoUrl,
        "-WorkRoot",
        $WorkRoot,
        "-CargoHome",
        $CargoHome,
        "-CargoTargetDir",
        $CargoTargetDir,
        "-PythonExe",
        $PythonExe,
        "-SkipBuild"
    )
}

$sourcePath = Get-PlannedSourceRoot -RequestedSourceRoot $sourcePath -Root $WorkRoot -Ref $RepoRef
$cargoRoot = Join-Path $sourcePath "codex-rs"
if (-not (Test-Path -LiteralPath (Join-Path $cargoRoot "Cargo.toml"))) {
    throw "Cargo root was not found: $cargoRoot"
}

Apply-CodeModeMuslStub -CargoRoot $cargoRoot -RustTarget $Target
if ($Target -eq "aarch64-unknown-linux-musl") {
    Update-CargoLockfile -CargoRoot $cargoRoot -CargoHomePath $CargoHome
}
$toolchain = Get-RepoToolchain -CargoRoot $cargoRoot
Ensure-RustTarget -Toolchain $toolchain -RustTarget $Target
$zigExe = Ensure-Zig -Directory $ZigDir -NoInstall:$SkipPrereqInstall
$cargoZigbuild = Ensure-CargoZigbuild -ToolsRoot $CargoToolsRoot -NoInstall:$SkipPrereqInstall
$perlTools = Ensure-StrawberryPerl -Root $StrawberryPerlRoot -NoInstall:$SkipPrereqInstall
$unixPerl = Ensure-UnixLikePerl -PerlExe $UnixPerlExe -Strawberry $perlTools

Write-Step "Tool versions"
Invoke-Checked -FilePath $zigExe -Arguments @("version")
Invoke-Checked -FilePath $cargoZigbuild -Arguments @("--version")
Invoke-Checked -FilePath $perlTools.GmakeExe -Arguments @("--version")
$oldToolPerl5Lib = $env:PERL5LIB
try {
    $env:PERL5LIB = $unixPerl.Perl5Lib
    Invoke-Checked -FilePath $unixPerl.PerlExe -Arguments @("-MLocale::Maketext::Simple", "-e", "print qq(unix perl ok\n)")
}
finally {
    $env:PERL5LIB = $oldToolPerl5Lib
}

Write-Step "Build"
New-Item -ItemType Directory -Force -Path $CargoHome | Out-Null
New-Item -ItemType Directory -Force -Path $CargoTargetDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "zig-cache") | Out-Null

$oldPath = $env:PATH
$oldCargoHome = $env:CARGO_HOME
$oldCargoTargetDir = $env:CARGO_TARGET_DIR
$oldZigGlobalCache = $env:ZIG_GLOBAL_CACHE_DIR
$oldPerl = $env:PERL
$oldPerl5Lib = $env:PERL5LIB
$oldMake = $env:MAKE
$oldMakeFlags = $env:MAKEFLAGS
$oldPython = $env:PYTHON
$oldMsys2EnvConvExcl = $env:MSYS2_ENV_CONV_EXCL
$targetEnvSuffix = $Target -replace "-", "_"
$targetEnvHyphen = $Target
$targetToolEnvNames = @(
    "CC_$targetEnvSuffix",
    "CXX_$targetEnvSuffix",
    "AR_$targetEnvSuffix",
    "RANLIB_$targetEnvSuffix",
    "CC_$targetEnvHyphen",
    "CXX_$targetEnvHyphen",
    "AR_$targetEnvHyphen",
    "RANLIB_$targetEnvHyphen",
    "CARGO_ZIGBUILD_ZIG_PATH",
    "CODEX_ZIGWRAP_ZIG_PATH"
)
$oldTargetToolEnv = @{}
foreach ($name in $targetToolEnvNames) {
    $oldTargetToolEnv[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}
try {
    $hostTools = New-HostBuildToolWrappers `
        -WrapperRoot (Join-Path $WorkRoot "build-tool-wrappers") `
        -GmakeExe $perlTools.GmakeExe
    $env:PATH = $hostTools.BinDir + ";" + $unixPerl.PerlBin + ";" + $perlTools.CBin + ";" + (Join-Path $CargoToolsRoot "bin") + ";" + $ZigDir + ";" + $env:PATH
    $env:CARGO_HOME = $CargoHome
    $env:CARGO_TARGET_DIR = $CargoTargetDir
    $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $WorkRoot "zig-cache"
    # OpenSSL writes the PERL value into its Makefile without robust shell
    # quoting. Keep Git's perl first on PATH, but use a space-free command name.
    $env:PERL = "perl"
    $env:PERL5LIB = $unixPerl.Perl5Lib
    if ($oldMsys2EnvConvExcl -and (($oldMsys2EnvConvExcl -split ";") -contains "PERL5LIB")) {
        $env:MSYS2_ENV_CONV_EXCL = $oldMsys2EnvConvExcl
    }
    elseif ($oldMsys2EnvConvExcl) {
        $env:MSYS2_ENV_CONV_EXCL = "$oldMsys2EnvConvExcl;PERL5LIB"
    }
    else {
        $env:MSYS2_ENV_CONV_EXCL = "PERL5LIB"
    }
    # openssl-src invokes "make" directly; keep it on a native gmake copy before
    # any MSYS make shim so PERL5LIB is not converted into Windows semicolon form.
    $env:MAKE = "make"
    $makeJobs = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount))
    if ($oldMakeFlags -and ($oldMakeFlags -match '(^|\s)-j')) {
        $env:MAKEFLAGS = $oldMakeFlags
    }
    elseif ($oldMakeFlags) {
        $env:MAKEFLAGS = "$oldMakeFlags -j$makeJobs"
    }
    else {
        $env:MAKEFLAGS = "-j$makeJobs"
    }
    $env:PYTHON = $PythonExe

    # cargo-zigbuild's generated .bat compiler wrappers use Windows backslashes.
    # OpenSSL later runs them from MSYS sh, which strips those backslashes. Use
    # stable forward-slash wrappers, not CC values containing arguments. AR uses
    # a native exe wrapper plus response files to avoid cmd.exe's short limit.
    $zigCcTarget = if ($Target -eq "aarch64-unknown-linux-musl") { "aarch64-linux-musl" } else { $Target }
    $targetTools = New-ZigbuildTargetToolWrappers `
        -WrapperRoot (Join-Path $WorkRoot "zigbuild-wrappers") `
        -RustTarget $Target `
        -ZigTarget $zigCcTarget `
        -CargoZigbuildExe $cargoZigbuild `
        -ZigExe $zigExe
    [Environment]::SetEnvironmentVariable("CARGO_ZIGBUILD_ZIG_PATH", $zigExe, "Process")
    [Environment]::SetEnvironmentVariable("CODEX_ZIGWRAP_ZIG_PATH", $zigExe, "Process")
    [Environment]::SetEnvironmentVariable("CC_$targetEnvSuffix", $targetTools.CC, "Process")
    [Environment]::SetEnvironmentVariable("CXX_$targetEnvSuffix", $targetTools.CXX, "Process")
    [Environment]::SetEnvironmentVariable("AR_$targetEnvSuffix", $targetTools.AR, "Process")
    [Environment]::SetEnvironmentVariable("RANLIB_$targetEnvSuffix", $targetTools.RANLIB, "Process")
    [Environment]::SetEnvironmentVariable("CC_$targetEnvHyphen", $targetTools.CC, "Process")
    [Environment]::SetEnvironmentVariable("CXX_$targetEnvHyphen", $targetTools.CXX, "Process")
    [Environment]::SetEnvironmentVariable("AR_$targetEnvHyphen", $targetTools.AR, "Process")
    [Environment]::SetEnvironmentVariable("RANLIB_$targetEnvHyphen", $targetTools.RANLIB, "Process")

    Invoke-Checked -FilePath $cargoZigbuild -Arguments @(
        "zigbuild",
        "-p",
        "codex-cli",
        "--bin",
        "codex",
        "--release",
        "--target",
        $Target,
        "--locked"
    ) -WorkingDirectory $cargoRoot
}
finally {
    $env:PATH = $oldPath
    $env:CARGO_HOME = $oldCargoHome
    $env:CARGO_TARGET_DIR = $oldCargoTargetDir
    $env:ZIG_GLOBAL_CACHE_DIR = $oldZigGlobalCache
    $env:PERL = $oldPerl
    $env:PERL5LIB = $oldPerl5Lib
    $env:MAKE = $oldMake
    $env:MAKEFLAGS = $oldMakeFlags
    $env:PYTHON = $oldPython
    $env:MSYS2_ENV_CONV_EXCL = $oldMsys2EnvConvExcl
    foreach ($name in $targetToolEnvNames) {
        [Environment]::SetEnvironmentVariable($name, $oldTargetToolEnv[$name], "Process")
    }
}

$builtBinary = Join-Path $CargoTargetDir (Join-Path $Target "release\codex")
if (-not (Test-Path -LiteralPath $builtBinary)) {
    throw "Expected built binary was not found: $builtBinary"
}

Write-Step "Copy artifact"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$artifactName = "codex-$versionLabel-zh-$Target"
$artifactPath = Join-Path $DistDir $artifactName
Copy-Item -LiteralPath $builtBinary -Destination $artifactPath -Force

if (-not $KeepDebugInfo) {
    $llvmStrip = Ensure-LlvmStrip -Toolchain $toolchain -NoInstall:$SkipPrereqInstall
    if ($llvmStrip) {
        Write-Step "Strip artifact"
        $strippedPath = "$artifactPath.strip-tmp"
        if (Test-Path -LiteralPath $strippedPath) {
            Remove-Item -LiteralPath $strippedPath -Force
        }
        Invoke-Checked -FilePath $llvmStrip -Arguments @("--strip-all", "-o", $strippedPath, $artifactPath)
        Move-Item -LiteralPath $strippedPath -Destination $artifactPath -Force
    }
    else {
        Write-Warning "llvm-strip.exe was not found; leaving unstripped artifact. Use -KeepDebugInfo to silence this."
    }
}

$artifact = Get-Item -LiteralPath $artifactPath
$hash = Get-Sha256Hex -Path $artifactPath
Write-Host "Artifact: $artifactPath"
Write-Host "Size:     $($artifact.Length) bytes"
Write-Host "SHA256:   $hash"

if ($PackageTarGz) {
    Write-Step "Package"
    $archivePath = Join-Path $DistDir "$artifactName.tar.gz"
    Invoke-Checked -FilePath "tar.exe" -Arguments @("-C", $DistDir, "-czf", $archivePath, $artifactName)
    Write-Host "Archive:  $archivePath"
}

Write-Step "Done"
Write-Host "This is an ARM64 Linux/musl ELF binary and cannot be executed on Windows."
