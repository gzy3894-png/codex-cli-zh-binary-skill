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
    [string]$PythonExe = "E:\tools\python\python.exe",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

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

    Invoke-Checked -FilePath "powershell" -Arguments (@(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $ScriptPath
    ) + $Arguments)
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
    $CargoTargetDir = Join-Path $WorkRoot ("target-zh-" + $versionLabel)
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

Write-Step "Plan"
Write-Host "Codex version: $(if ($version) { $version } else { 'unknown' })"
Write-Host "Repo ref:      $RepoRef"
Write-Host "Work root:     $WorkRoot"
Write-Host "Source root:   $(if ($SourceRoot) { $SourceRoot } else { Join-Path $WorkRoot ('codex-' + ($RepoRef -replace '[^A-Za-z0-9._-]', '-')) })"
Write-Host "Cargo home:    $CargoHome"
Write-Host "Cargo target:  $CargoTargetDir"
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
        Write-Host "Existing source found; underlying patch scripts can be dry-run directly if needed."
    }
    else {
        Write-Host "Source is not present yet; a real run would clone it with sparse checkout."
    }
    exit 0
}

$sourcePath = Resolve-SourceRoot -RequestedSourceRoot $SourceRoot -Root $WorkRoot -Ref $RepoRef -Url $RepoUrl

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
    "-PythonExe", $PythonExe
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

Invoke-PatchScript -ScriptPath $deepScript -Arguments $deepArgs

Write-Step "Done"
if ($SkipBuild) {
    Write-Host "Source patching is complete. Re-run without -SkipBuild to build once from the combined patched source."
}
else {
    $builtExe = Join-Path $CargoTargetDir "release\codex.exe"
    Write-Host "Built exe: $builtExe"
    if (Test-Path -LiteralPath $builtExe) {
        & $builtExe --version
    }
}
