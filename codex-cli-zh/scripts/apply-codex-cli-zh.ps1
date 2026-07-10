[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Install,
    [switch]$UseWrapperOverride,
    [string]$SourceRoot = "",
    [string]$RepoRef = "",
    [string]$RepoUrl = "https://github.com/openai/codex.git",
    [string]$WorkRoot = "E:\cz",
    [string]$CargoHome = "E:\cz\cargo-home",
    [string]$CargoTargetDir = "",
    [string]$PythonExe = "",
    [ValidateRange(0, 64)][int]$BuildJobs = 0,
    [switch]$LowMemoryBuild,
    [switch]$AllowConcurrentBuild,
    [string]$BuildLog = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:PatchPowerShell = ""

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

function Resolve-SourceRoot {
    param(
        [string]$RequestedSourceRoot,
        [string]$Root,
        [string]$Ref,
        [string]$Url,
        [switch]$NoClone
    )

    if ($RequestedSourceRoot) {
        return (Resolve-Path -LiteralPath $RequestedSourceRoot -ErrorAction Stop).Path
    }

    $safeRef = $Ref -replace "[^A-Za-z0-9._-]", "-"
    $path = Join-Path $Root ("codex-" + $safeRef)

    if (Test-Path -LiteralPath $path) {
        return (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
    }

    if ($NoClone) {
        return $path
    }

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Invoke-Checked -FilePath "git" -Arguments @(
        "clone",
        "--filter=blob:none",
        "--sparse",
        "--depth",
        "1",
        "--branch",
        $Ref,
        $Url,
        $path
    )
    Invoke-Checked -FilePath "git" -Arguments @(
        "-C",
        $path,
        "sparse-checkout",
        "set",
        "codex-rs"
    )

    return (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
}

function Invoke-PatchScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    Invoke-Checked -FilePath $script:PatchPowerShell -Arguments (@(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $ScriptPath
    ) + $Arguments)
}

function Resolve-PatchPowerShell {
    foreach ($name in @("pwsh", "powershell")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            return $command.Source
        }
    }

    throw "Neither pwsh nor powershell is available to run the bundled patch scripts."
}

function Assert-SourceMatchesRef {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Ref
    )

    $hasRepoLayout = Test-Path -LiteralPath (Join-Path $Path "codex-rs\Cargo.toml")
    $hasRsLayout = (
        (Test-Path -LiteralPath (Join-Path $Path "Cargo.toml")) -and
        (Test-Path -LiteralPath (Join-Path $Path "tui\src"))
    )
    if (-not $hasRepoLayout -and -not $hasRsLayout) {
        throw "Existing source is incomplete or is not a Codex Rust checkout: $Path"
    }

    $headOutput = @(& git -C $Path rev-parse HEAD 2>$null)
    $headExitCode = $LASTEXITCODE
    $head = ($headOutput | Select-Object -First 1)
    if ($headExitCode -ne 0 -or -not $head) {
        throw "Existing source is not a readable Git checkout: $Path"
    }

    $refOutput = @(& git -C $Path rev-list -n 1 $Ref 2>$null)
    $refExitCode = $LASTEXITCODE
    $refCommit = ($refOutput | Select-Object -First 1)
    if ($refExitCode -ne 0 -or -not $refCommit) {
        throw "Existing source does not contain requested ref ${Ref}: $Path"
    }
    if ($head.Trim() -ne $refCommit.Trim()) {
        throw "Existing source HEAD $($head.Trim()) does not match ${Ref} ($($refCommit.Trim())): $Path"
    }
}

$version = Get-CodexVersion
if (-not $RepoRef) {
    if ($version) {
        $RepoRef = "rust-v$version"
    }
    else {
        throw "Could not determine the installed Codex version. Pass -RepoRef explicitly instead of building an unpinned main checkout."
    }
}

$versionLabel = Get-VersionLabel -Version $version -Ref $RepoRef
if (-not $CargoTargetDir) {
    $CargoTargetDir = Join-Path $WorkRoot ("target-zh-" + $versionLabel)
}
if (-not $BuildLog) {
    $buildStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BuildLog = Join-Path $WorkRoot ("logs\codex-$versionLabel-windows-build-$buildStamp.log")
}

$slashScript = Join-Path $PSScriptRoot "patch-codex-slash-zh.ps1"
$deepScript = Join-Path $PSScriptRoot "patch-codex-cli-zh-deep.ps1"
$slashMap = Join-Path $PSScriptRoot "slash-command-translations.zh.json"
$deepMap = Join-Path $PSScriptRoot "deep-translations.zh.json"

foreach ($required in @($slashScript, $deepScript, $slashMap, $deepMap)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required bundled resource: $required"
    }
}
$script:PatchPowerShell = Resolve-PatchPowerShell

Write-Step "Plan"
Write-Host "Codex version: $(if ($version) { $version } else { 'unknown' })"
Write-Host "Repo ref:      $RepoRef"
Write-Host "Work root:     $WorkRoot"
Write-Host "Source root:   $(if ($SourceRoot) { $SourceRoot } else { Join-Path $WorkRoot ('codex-' + ($RepoRef -replace '[^A-Za-z0-9._-]', '-')) })"
Write-Host "Cargo home:    $CargoHome"
Write-Host "Cargo target:  $CargoTargetDir"
Write-Host "Build log:     $BuildLog"
Write-Host "Build jobs:    $(if ($BuildJobs -gt 0) { $BuildJobs } else { 'auto' })"
Write-Host "Low memory:    $LowMemoryBuild"
Write-Host "Concurrent:    $AllowConcurrentBuild"
Write-Host "Patch host:    $script:PatchPowerShell"
Write-Host "Install:       $Install"
Write-Host "Wrapper mode:  $UseWrapperOverride"
Write-Host "Skip build:    $SkipBuild"

if ($Install -and -not $UseWrapperOverride -and $env:OS -eq "Windows_NT") {
    Write-Host "Warning: on Windows, -UseWrapperOverride is safer because running codex.exe files are often locked."
}

if ($DryRun) {
    $plannedSource = Resolve-SourceRoot -RequestedSourceRoot $SourceRoot -Root $WorkRoot -Ref $RepoRef -Url $RepoUrl -NoClone
    Write-Step "Dry run"
    Write-Host "No source files, build artifacts, npm packages, or wrapper files were changed."
    Write-Host "Planned source: $plannedSource"
    if (Test-Path -LiteralPath $plannedSource) {
        Assert-SourceMatchesRef -Path $plannedSource -Ref $RepoRef
        Write-Host "Existing source found; underlying patch scripts can be dry-run directly if needed."
    }
    else {
        Write-Host "Source is not present yet; a real run would clone it with sparse checkout."
    }
    exit 0
}

$sourcePath = Resolve-SourceRoot -RequestedSourceRoot $SourceRoot -Root $WorkRoot -Ref $RepoRef -Url $RepoUrl
Assert-SourceMatchesRef -Path $sourcePath -Ref $RepoRef

Write-Step "Patch slash command strings"
$slashArgs = @(
    "-SourceRoot", $sourcePath,
    "-RepoRef", $RepoRef,
    "-WorkRoot", $WorkRoot,
    "-MapFile", $slashMap,
    "-CargoHome", $CargoHome,
    "-CargoTargetDir", $CargoTargetDir,
    "-PythonExe", $PythonExe,
    "-SkipBuild"
)
Invoke-PatchScript -ScriptPath $slashScript -Arguments $slashArgs

Write-Step "Patch deep TUI strings"
$deepArgs = @(
    "-SourceRoot", $sourcePath,
    "-MapFile", $deepMap,
    "-CargoHome", $CargoHome,
    "-CargoTargetDir", $CargoTargetDir,
    "-PythonExe", $PythonExe,
    "-BuildJobs", "$BuildJobs",
    "-BuildLog", $BuildLog
)

if ($SkipBuild) {
    $deepArgs += "-SkipBuild"
}
if ($Install) {
    $deepArgs += "-Install"
}
if ($UseWrapperOverride) {
    $deepArgs += "-UseWrapperOverride"
}
if ($LowMemoryBuild) {
    $deepArgs += "-LowMemoryBuild"
}
if ($AllowConcurrentBuild) {
    $deepArgs += "-AllowConcurrentBuild"
}

Invoke-PatchScript -ScriptPath $deepScript -Arguments $deepArgs

Write-Step "Done"
if ($SkipBuild) {
    Write-Host "Source patching is complete. Re-run without -SkipBuild to build once from the combined patched source."
}
else {
    $builtExe = Join-Path $CargoTargetDir "release\codex.exe"
    Write-Host "Built exe: $builtExe"
    if (-not (Test-Path -LiteralPath $builtExe)) {
        throw "Build completed without the expected executable: $builtExe"
    }
    $builtVersionLine = (& $builtExe --version 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or $builtVersionLine -notmatch "codex-cli\s+([^\s]+)") {
        throw "Built executable could not report a valid Codex version: $builtExe"
    }
    $builtVersion = $Matches[1]
    if ($RepoRef -match "^rust-v(.+)$" -and $builtVersion -ne $Matches[1]) {
        throw "Built version $builtVersion does not match requested ref $RepoRef. Refusing to install or report success."
    }
    Write-Host "Built version: $builtVersion"
}
