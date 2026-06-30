[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Install,
    [switch]$UseWrapperOverride,
    [string]$SourceRoot = "",
    [string]$RepoRef = "",
    [string]$RepoUrl = "https://github.com/openai/codex.git",
    [string]$WorkRoot = "E:\cz",
    [string]$MapFile = "",
    [string]$TargetExe = "",
    [string]$BuiltExe = "",
    [string]$PythonExe = "",
    [string]$RustyV8Archive = "",
    [string]$CargoHome = "",
    [string]$CargoTargetDir = "",
    [switch]$SkipBuild,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if (-not $MapFile) {
    $MapFile = Join-Path $PSScriptRoot "slash-command-translations.zh.json"
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message"
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = ""
    )

    $display = $FilePath + " " + ($Arguments -join " ")
    if ($WorkingDirectory) {
        Write-Host ">> [$WorkingDirectory] $display"
        Push-Location -LiteralPath $WorkingDirectory
        try {
            & $FilePath @Arguments
            if ($LASTEXITCODE -ne 0) {
                throw "Command failed with exit code ${LASTEXITCODE}: $display"
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Host ">> $display"
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $display"
        }
    }
}

function Resolve-UsableCommand {
    param([string[]]$Names)

    foreach ($name in $Names) {
        if (-not $name) {
            continue
        }

        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) {
            continue
        }

        if ($cmd.Source -like "*\WindowsApps\*") {
            continue
        }

        return $cmd.Source
    }

    return ""
}

function Resolve-UsablePython {
    param([string]$RequestedPython)

    $candidates = @()
    if ($RequestedPython) {
        $candidates += $RequestedPython
    }
    if ($env:PYTHON) {
        $candidates += $env:PYTHON
    }
    $candidates += @("E:\tools\python\python.exe", "python.exe", "py.exe")

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }

        $path = ""
        if (Test-Path -LiteralPath $candidate) {
            $path = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
        else {
            $path = Resolve-UsableCommand -Names @($candidate)
        }

        if (-not $path -or $path -like "*\WindowsApps\*") {
            continue
        }

        try {
            $version = (& $path --version 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -eq 0 -and $version) {
                return [pscustomobject]@{
                    Path = $path
                    Version = $version
                }
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-CodexVersion {
    $versionLine = ""
    try {
        $versionLine = (& codex --version 2>$null | Select-Object -First 1)
    }
    catch {
        $versionLine = ""
    }

    if ($versionLine -match "(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)") {
        return $Matches[1]
    }

    return ""
}

function Resolve-CodexNativeExe {
    param([string]$RequestedTarget)

    if ($RequestedTarget) {
        $resolved = Resolve-Path -LiteralPath $RequestedTarget -ErrorAction Stop
        return $resolved.Path
    }

    try {
        $doctor = (& codex doctor --summary --ascii --no-color 2>$null) -join "`n"
        if ($doctor -match "runtime\s+npm \(package .+?, bin ([^,\)]+)") {
            $candidate = Join-Path $Matches[1].Trim() "codex.exe"
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    catch {
        # Fall through to npm shim probing.
    }

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $baseDir = Split-Path -Parent $cmd.Source
        $glob = Join-Path $baseDir "node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\*\bin\codex.exe"
        $matches = @(Get-ChildItem -Path $glob -ErrorAction SilentlyContinue)
        if ($matches.Count -gt 0) {
            return $matches[0].FullName
        }
    }

    throw "Could not locate the installed native codex.exe. Pass -TargetExe explicitly."
}

function Install-CodexNodeWrapperOverride {
    param(
        [Parameter(Mandatory = $true)][string]$NativeExe,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )

    $resolvedNativeExe = (Resolve-Path -LiteralPath $NativeExe -ErrorAction Stop).Path
    $cmd = Get-Command codex -ErrorAction Stop
    $baseDir = Split-Path -Parent $cmd.Source
    $codexJs = Join-Path $baseDir "node_modules\@openai\codex\bin\codex.js"
    if (-not (Test-Path -LiteralPath $codexJs)) {
        throw "Could not locate codex.js wrapper: $codexJs"
    }

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $wrapperBackup = Join-Path $BackupDir ("codex.js.$timestamp.bak")
    Copy-Item -LiteralPath $codexJs -Destination $wrapperBackup -Force

    $content = Get-Content -LiteralPath $codexJs -Raw -Encoding UTF8
    $jsonPath = $resolvedNativeExe | ConvertTo-Json -Compress
    $override = @"
// codex-cli-zh-slash-patch start
const localWindowsBinaryPath = $jsonPath;
const binaryPath =
  process.platform === "win32" && existsSync(localWindowsBinaryPath)
    ? localWindowsBinaryPath
    : findCodexExecutable();
// codex-cli-zh-slash-patch end
"@

    $markerPattern = "(?s)// codex-cli-zh-slash-patch start.*?// codex-cli-zh-slash-patch end"
    $manualPattern = "(?s)// Prefer the locally rebuilt zh-patched binary when present\.\r?\nconst localWindowsBinaryPath = .*?\r?\nconst binaryPath =\r?\n  process\.platform === ""win32"" && existsSync\(localWindowsBinaryPath\)\r?\n    \? localWindowsBinaryPath\r?\n    : findCodexExecutable\(\);"

    if ([regex]::IsMatch($content, $markerPattern)) {
        $content = [regex]::Replace($content, $markerPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $override }, 1)
    }
    elseif ([regex]::IsMatch($content, $manualPattern)) {
        $content = [regex]::Replace($content, $manualPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $override }, 1)
    }
    elseif ($content.Contains("const binaryPath = findCodexExecutable();")) {
        $content = $content.Replace("const binaryPath = findCodexExecutable();", $override)
    }
    else {
        throw "Could not find binaryPath assignment in codex.js; wrapper override was not installed."
    }

    [System.IO.File]::WriteAllText($codexJs, $content, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        WrapperPath = $codexJs
        BackupPath = $wrapperBackup
        NativeExe = $resolvedNativeExe
    }
}

function Resolve-SourceLayout {
    param([string]$Root)

    $rootPath = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
    $candidateFromRepo = Join-Path $rootPath "codex-rs\tui\src\slash_command.rs"
    $candidateFromRustRoot = Join-Path $rootPath "tui\src\slash_command.rs"

    if (Test-Path -LiteralPath $candidateFromRepo) {
        return [pscustomobject]@{
            RepoRoot = $rootPath
            CodexRsRoot = (Join-Path $rootPath "codex-rs")
            SlashFile = $candidateFromRepo
        }
    }

    if (Test-Path -LiteralPath $candidateFromRustRoot) {
        return [pscustomobject]@{
            RepoRoot = (Split-Path -Parent $rootPath)
            CodexRsRoot = $rootPath
            SlashFile = $candidateFromRustRoot
        }
    }

    throw "Could not find codex-rs\tui\src\slash_command.rs under: $Root"
}

function Read-TranslationMap {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Translation map not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $items = @($json | ConvertFrom-Json)
    if ($items.Count -eq 0) {
        throw "Translation map is empty: $Path"
    }

    foreach ($item in $items) {
        if (-not $item.from -or -not $item.to) {
            throw "Each translation map item must contain non-empty 'from' and 'to' fields."
        }
    }

    return $items
}

function Patch-SlashCommandFile {
    param(
        [string]$SlashFile,
        [object[]]$Map
    )

    $content = Get-Content -LiteralPath $SlashFile -Raw -Encoding UTF8
    $missing = New-Object System.Collections.Generic.List[string]
    $changed = 0
    $already = 0

    foreach ($item in $Map) {
        $from = [string]$item.from
        $to = [string]$item.to
        $count = [regex]::Matches($content, [regex]::Escape($from)).Count

        if ($count -eq 0) {
            if ($content.Contains($to)) {
                $already += 1
                continue
            }

            $missing.Add($from)
            continue
        }

        $content = $content.Replace($from, $to)
        $changed += $count
    }

    if ($missing.Count -gt 0) {
        $sample = ($missing | Select-Object -First 8) -join "`n  - "
        throw "Some expected English descriptions were not found and are not already translated. Review the map for upstream wording changes:`n  - $sample"
    }

    [System.IO.File]::WriteAllText($SlashFile, $content, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        ChangedOccurrences = $changed
        AlreadyTranslated = $already
    }
}

function New-ClonePath {
    param(
        [string]$Root,
        [string]$Ref,
        [switch]$AllowForce
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeRef = $Ref -replace "[^A-Za-z0-9._-]", "-"
    $path = Join-Path $Root ("codex-" + $safeRef)

    if (Test-Path -LiteralPath $path) {
        if ($AllowForce) {
            $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
            $fullPath = [System.IO.Path]::GetFullPath($path).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
            if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove path outside WorkRoot: $path"
            }
            Remove-Item -LiteralPath $path -Recurse -Force
        }
        else {
            $path = "$path-$timestamp"
        }
    }

    return $path
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

Write-Step "Plan"
Write-Host "Codex version: $(if ($version) { $version } else { 'unknown' })"
Write-Host "Repo ref:      $RepoRef"
Write-Host "Work root:     $WorkRoot"
Write-Host "Map file:      $MapFile"

$target = ""
try {
    $target = Resolve-CodexNativeExe -RequestedTarget $TargetExe
    Write-Host "Target exe:    $target"
}
catch {
    Write-Host "Target exe:    not resolved yet ($($_.Exception.Message))"
}

Write-Step "Toolchain"
foreach ($tool in @("git", "cargo", "rustc")) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Required tool not found on PATH: $tool"
    }
    Write-Host ("{0,-6} {1}" -f $tool, $cmd.Source)
}

$python = Resolve-UsablePython -RequestedPython $PythonExe
if ($python) {
    $env:PYTHON = $python.Path
    Write-Host ("{0,-6} {1} ({2})" -f "python", $python.Path, $python.Version)
}
else {
    Write-Host "python not resolved; V8 build script will fall back to curl if needed."
}

if ($RustyV8Archive) {
    $RustyV8Archive = (Resolve-Path -LiteralPath $RustyV8Archive -ErrorAction Stop).Path
    $env:RUSTY_V8_ARCHIVE = $RustyV8Archive
    Write-Host "RUSTY_V8_ARCHIVE: $RustyV8Archive"
}

if (-not $CargoHome) {
    $CargoHome = Join-Path $WorkRoot "cargo-home"
}
if (-not $CargoTargetDir) {
    $CargoTargetDir = Join-Path $WorkRoot "target"
}
Write-Host "CARGO_HOME:    $CargoHome"
Write-Host "Cargo target:  $CargoTargetDir"

$map = Read-TranslationMap -Path $MapFile
Write-Host "Translations: $($map.Count)"

if ($DryRun) {
    Write-Step "Dry run complete"
    Write-Host "No source files, build artifacts, or installed binaries were changed."
    exit 0
}

New-Item -ItemType Directory -Force -Path $CargoHome | Out-Null
New-Item -ItemType Directory -Force -Path $CargoTargetDir | Out-Null
$env:CARGO_HOME = (Resolve-Path -LiteralPath $CargoHome -ErrorAction Stop).Path
$env:CARGO_TARGET_DIR = (Resolve-Path -LiteralPath $CargoTargetDir -ErrorAction Stop).Path

Write-Step "Source"
$sourcePath = $SourceRoot
if (-not $sourcePath) {
    New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
    $sourcePath = New-ClonePath -Root $WorkRoot -Ref $RepoRef -AllowForce:$Force
    Invoke-Checked -FilePath "git" -Arguments @("clone", "--filter=blob:none", "--sparse", "--depth", "1", "--branch", $RepoRef, $RepoUrl, $sourcePath)
    Invoke-Checked -FilePath "git" -Arguments @("-C", $sourcePath, "sparse-checkout", "set", "codex-rs")
}
else {
    Write-Host "Using existing source: $sourcePath"
}

$layout = Resolve-SourceLayout -Root $sourcePath
Write-Host "Slash source:  $($layout.SlashFile)"
Write-Host "Cargo root:    $($layout.CodexRsRoot)"

Write-Step "Patch"
$patchResult = Patch-SlashCommandFile -SlashFile $layout.SlashFile -Map $map
Write-Host "Changed occurrences: $($patchResult.ChangedOccurrences)"
Write-Host "Already translated:  $($patchResult.AlreadyTranslated)"

if (-not $SkipBuild) {
    Write-Step "Build"
    Invoke-Checked -FilePath "cargo" -Arguments @("build", "--release", "-p", "codex-cli") -WorkingDirectory $layout.CodexRsRoot
    $BuiltExe = Join-Path $env:CARGO_TARGET_DIR "release\codex.exe"
}
elseif (-not $BuiltExe) {
    $candidateBuiltExe = Join-Path $env:CARGO_TARGET_DIR "release\codex.exe"
    if (Test-Path -LiteralPath $candidateBuiltExe) {
        $BuiltExe = $candidateBuiltExe
    }
}

if (-not $BuiltExe -or -not (Test-Path -LiteralPath $BuiltExe)) {
    if ($SkipBuild) {
        Write-Step "Skipped build"
        Write-Host "Source was patched. No built codex.exe was found because -SkipBuild was used."
        exit 0
    }
    throw "Build did not produce codex.exe."
}

$BuiltExe = (Resolve-Path -LiteralPath $BuiltExe).Path
Write-Host "Built exe:     $BuiltExe"
try {
    $builtVersion = (& $BuiltExe --version 2>$null | Select-Object -First 1)
    Write-Host "Built version: $builtVersion"
}
catch {
    Write-Host "Built version: could not run built exe: $($_.Exception.Message)"
}

if (-not $Install) {
    Write-Step "Done"
    Write-Host "Patched binary is ready but not installed. Re-run with -Install to replace the current native codex.exe."
    exit 0
}

Write-Step "Install"
if (-not $target) {
    $target = Resolve-CodexNativeExe -RequestedTarget $TargetExe
}

$backupDir = Join-Path $env:USERPROFILE ".codex\backups\cli-zh-slash"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

if ($UseWrapperOverride) {
    $wrapper = Install-CodexNodeWrapperOverride -NativeExe $BuiltExe -BackupDir $backupDir
    Write-Host "Wrapper:       $($wrapper.WrapperPath)"
    Write-Host "Wrapper backup:$($wrapper.BackupPath)"
    Write-Host "Native exe:    $($wrapper.NativeExe)"
    Write-Host ""
    Write-Host "Restart Codex CLI, type '/', and check that command descriptions are Chinese."
    exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $backupDir ("codex.exe.$timestamp.bak")

Copy-Item -LiteralPath $target -Destination $backup -Force
Write-Host "Backup:        $backup"

try {
    Copy-Item -LiteralPath $BuiltExe -Destination $target -Force
}
catch {
    Write-Host "Install failed after backup. The target binary may be locked by a running Codex process."
    Write-Host "Built exe remains at: $BuiltExe"
    Write-Host "Installing Node wrapper override instead."
    $wrapper = Install-CodexNodeWrapperOverride -NativeExe $BuiltExe -BackupDir $backupDir
    Write-Host "Wrapper:       $($wrapper.WrapperPath)"
    Write-Host "Wrapper backup:$($wrapper.BackupPath)"
    Write-Host "Native exe:    $($wrapper.NativeExe)"
    Write-Host ""
    Write-Host "Restart Codex CLI, type '/', and check that command descriptions are Chinese."
    exit 0
}

Write-Host "Installed:     $target"
try {
    $installedVersion = (& $target --version 2>$null | Select-Object -First 1)
    Write-Host "Installed ver: $installedVersion"
}
catch {
    Write-Host "Installed ver: could not run installed exe: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Restart Codex CLI, type '/', and check that command descriptions are Chinese."
