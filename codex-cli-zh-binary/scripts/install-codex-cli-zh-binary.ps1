[CmdletBinding()]
param(
    [string]$BinaryPath = "",
    [string]$DownloadUrl = "https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/latest/download/codex-cli-zh-windows-x64.exe",
    [string]$ExpectedSha256 = "",
    [string]$InstallDir = "$env:LOCALAPPDATA\codex-cli-zh-binary\bin",
    [string]$CodexCommand = "codex",
    [string]$WrapperPath = "",
    [string]$BackupDir = "$env:USERPROFILE\.codex\backups\codex-cli-zh-binary",
    [switch]$Restore,
    [switch]$RemoveOverride,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$DefaultDownloadUrl = "https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/latest/download/codex-cli-zh-windows-x64.exe"
$DefaultReleaseSha256 = "0DD8649E0C19FA57590D2F7B674FFDFE278744E2DCCC4036C28DB168B2E073A5"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message"
}

function Resolve-ExistingPath {
    param([string]$Path)
    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
}

function Get-CodexWrapperPath {
    param(
        [string]$CommandName,
        [string]$RequestedWrapperPath
    )

    if ($RequestedWrapperPath) {
        $resolved = Resolve-ExistingPath -Path $RequestedWrapperPath
        if ((Split-Path -Leaf $resolved) -ne "codex.js") {
            throw "WrapperPath must point to codex.js: $resolved"
        }
        return $resolved
    }

    $commands = @(Get-Command $CommandName -All -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        throw "Could not find '$CommandName' on PATH. Install @openai/codex with npm first, or pass -WrapperPath."
    }

    $checked = New-Object System.Collections.Generic.List[string]
    foreach ($command in $commands) {
        if (-not $command.Source) {
            continue
        }

        $source = $command.Source
        try {
            $source = Resolve-ExistingPath -Path $source
        }
        catch {
            $checked.Add($command.Source)
            continue
        }

        $candidates = New-Object System.Collections.Generic.List[string]
        if ((Split-Path -Leaf $source) -eq "codex.js") {
            $candidates.Add($source)
        }

        $shimDir = Split-Path -Parent $source
        $candidates.Add((Join-Path $shimDir "node_modules\@openai\codex\bin\codex.js"))

        foreach ($candidate in $candidates) {
            $checked.Add($candidate)
            if (-not (Test-Path -LiteralPath $candidate)) {
                continue
            }

            $content = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8
            if ($content.Contains("findCodexExecutable")) {
                return (Resolve-ExistingPath -Path $candidate)
            }
        }
    }

    $sample = ($checked | Select-Object -Unique | Select-Object -First 12) -join "`n  - "
    throw "Could not resolve the npm Codex wrapper for '$CommandName'. Checked:`n  - $sample`nPass -WrapperPath if this Codex install uses a custom layout."
}

function Test-CodexExeInUse {
    param([string]$ExePath)

    if (-not (Test-Path -LiteralPath $ExePath)) {
        return $false
    }

    $resolved = Resolve-ExistingPath -Path $ExePath
    $running = @(
        Get-CimInstance Win32_Process -Filter "Name = 'codex.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $resolved }
    )

    return ($running.Count -gt 0)
}

function Assert-ExpectedSha256 {
    param(
        [string]$Path,
        [string]$Expected
    )

    if (-not $Expected) {
        return
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    $expectedUpper = $Expected.ToUpperInvariant()
    if ($actual -ne $expectedUpper) {
        throw "SHA256 mismatch for $Path. Expected $expectedUpper but got $actual."
    }

    Write-Host "SHA256:    $actual"
}

function Ensure-ExistsSyncImport {
    param([string]$Content)

    if ($Content.Contains("existsSync")) {
        return $Content
    }

    $fsImportPattern = 'import\s+\{([^}]+)\}\s+from\s+"fs";'
    if ([regex]::IsMatch($Content, $fsImportPattern)) {
        return [regex]::Replace(
            $Content,
            $fsImportPattern,
            {
                param($match)
                $items = $match.Groups[1].Value.Trim()
                if ($items -match '(^|,\s*)existsSync(\s*,|$)') {
                    return $match.Value
                }
                return "import { existsSync, $items } from ""fs"";"
            },
            1
        )
    }

    if ($Content.StartsWith("#!/usr/bin/env node`n")) {
        return $Content.Replace("#!/usr/bin/env node`n", "#!/usr/bin/env node`nimport { existsSync } from ""fs"";`n")
    }

    return "import { existsSync } from ""fs"";`n" + $Content
}

function Backup-Wrapper {
    param(
        [string]$CodexJs,
        [string]$DestinationDir
    )

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $DestinationDir "codex.js.$stamp.bak"
    Copy-Item -LiteralPath $CodexJs -Destination $backup -Force
    return $backup
}

function Get-InstallBinary {
    param(
        [string]$SourceBinary,
        [string]$Url,
        [string]$DestinationDir
    )

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    $target = Join-Path $DestinationDir "codex.exe"

    if (Test-CodexExeInUse -ExePath $target) {
        throw "Target binary is currently running and cannot be replaced: $target. Close old Codex CLI sessions first."
    }

    if ($SourceBinary) {
        $source = Resolve-ExistingPath -Path $SourceBinary
        if ((Split-Path -Leaf $source) -ne "codex.exe") {
            Write-Host "Warning: source file is not named codex.exe; it will still be copied as codex.exe."
        }

        if ($source -ine $target) {
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
    else {
        $tmp = Join-Path $DestinationDir "codex.exe.download"
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force
        }
        Write-Host "Downloading: $Url"
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
        Move-Item -LiteralPath $tmp -Destination $target -Force
    }

    if (-not (Test-Path -LiteralPath $target)) {
        throw "Binary install failed: $target"
    }

    return (Resolve-ExistingPath -Path $target)
}

function Write-WrapperOverride {
    param(
        [string]$CodexJs,
        [string]$NativeExe
    )

    $content = Get-Content -LiteralPath $CodexJs -Raw -Encoding UTF8
    if (-not $content.Contains("findCodexExecutable")) {
        throw "Wrapper does not look like the npm Codex wrapper: $CodexJs"
    }

    $content = Ensure-ExistsSyncImport -Content $content
    $jsonPath = (Resolve-ExistingPath -Path $NativeExe) | ConvertTo-Json -Compress
    $override = @"
// codex-cli-zh-binary start
const localWindowsBinaryPath = $jsonPath;
const binaryPath =
  process.platform === "win32" && existsSync(localWindowsBinaryPath)
    ? localWindowsBinaryPath
    : findCodexExecutable();
// codex-cli-zh-binary end
"@

    $patterns = @(
        "(?s)// codex-cli-zh-binary start.*?// codex-cli-zh-binary end",
        "(?s)// codex-cli-zh-deep-patch start.*?// codex-cli-zh-deep-patch end",
        "(?s)// codex-cli-zh-slash-patch start.*?// codex-cli-zh-slash-patch end"
    )

    $changed = $false
    foreach ($pattern in $patterns) {
        if ([regex]::IsMatch($content, $pattern)) {
            $content = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $override }, 1)
            $changed = $true
            break
        }
    }

    if (-not $changed) {
        $plain = "const binaryPath = findCodexExecutable();"
        if (-not $content.Contains($plain)) {
            throw "Could not find a known binaryPath assignment in codex.js. Refusing to patch an unknown wrapper shape."
        }
        $content = $content.Replace($plain, $override)
    }

    [System.IO.File]::WriteAllText($CodexJs, $content, [System.Text.UTF8Encoding]::new($false))
}

function Remove-WrapperOverride {
    param([string]$CodexJs)

    $content = Get-Content -LiteralPath $CodexJs -Raw -Encoding UTF8
    $pattern = "(?s)// codex-cli-zh-binary start.*?// codex-cli-zh-binary end"
    if (-not [regex]::IsMatch($content, $pattern)) {
        throw "No codex-cli-zh-binary override block found in: $CodexJs"
    }

    $content = [regex]::Replace($content, $pattern, "const binaryPath = findCodexExecutable();", 1)
    [System.IO.File]::WriteAllText($CodexJs, $content, [System.Text.UTF8Encoding]::new($false))
}

function Restore-LatestBackup {
    param(
        [string]$CodexJs,
        [string]$SourceBackupDir
    )

    if (-not (Test-Path -LiteralPath $SourceBackupDir)) {
        throw "Backup directory does not exist: $SourceBackupDir"
    }

    $latest = Get-ChildItem -LiteralPath $SourceBackupDir -Filter "codex.js.*.bak" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No wrapper backup found in: $SourceBackupDir"
    }

    Copy-Item -LiteralPath $latest.FullName -Destination $CodexJs -Force
    return $latest.FullName
}

if ($env:OS -ne "Windows_NT") {
    throw "This prebuilt binary installer is Windows-only."
}

if (-not $ExpectedSha256 -and -not $BinaryPath -and $DownloadUrl -eq $DefaultDownloadUrl) {
    $ExpectedSha256 = $DefaultReleaseSha256
}

Write-Step "Resolve Codex wrapper"
$codexJs = Get-CodexWrapperPath -CommandName $CodexCommand -RequestedWrapperPath $WrapperPath
Write-Host "Wrapper: $codexJs"

if ($Restore) {
    if ($DryRun) {
        Write-Host "DryRun: would restore latest backup from $BackupDir"
        exit 0
    }

    $restored = Restore-LatestBackup -CodexJs $codexJs -SourceBackupDir $BackupDir
    Write-Host "Restored wrapper backup: $restored"
    exit 0
}

if ($RemoveOverride) {
    if ($DryRun) {
        Write-Host "DryRun: would remove codex-cli-zh-binary override from $codexJs"
        exit 0
    }

    $backup = Backup-Wrapper -CodexJs $codexJs -DestinationDir $BackupDir
    Remove-WrapperOverride -CodexJs $codexJs
    Write-Host "Backup:  $backup"
    Write-Host "Removed override. New Codex sessions will use the official binary resolver."
    exit 0
}

Write-Step "Plan"
Write-Host "Binary source: $(if ($BinaryPath) { $BinaryPath } else { $DownloadUrl })"
Write-Host "Expected SHA:  $(if ($ExpectedSha256) { $ExpectedSha256 } else { '(not checked)' })"
Write-Host "Install dir:   $InstallDir"
Write-Host "Backup dir:    $BackupDir"

if ($DryRun) {
    Write-Host "DryRun: no files were changed."
    exit 0
}

Write-Step "Install binary"
$nativeExe = Get-InstallBinary -SourceBinary $BinaryPath -Url $DownloadUrl -DestinationDir $InstallDir
Write-Host "Native exe: $nativeExe"
Assert-ExpectedSha256 -Path $nativeExe -Expected $ExpectedSha256
try {
    $version = (& $nativeExe --version 2>$null | Select-Object -First 1)
    Write-Host "Version:    $version"
}
catch {
    Write-Host "Warning: installed binary could not be executed for version check: $($_.Exception.Message)"
}

Write-Step "Patch wrapper"
$backupPath = Backup-Wrapper -CodexJs $codexJs -DestinationDir $BackupDir
Write-WrapperOverride -CodexJs $codexJs -NativeExe $nativeExe
Write-Host "Backup:  $backupPath"
Write-Host "Wrapper: $codexJs"

Write-Step "Verify"
try {
    $activeVersion = (& $CodexCommand --version 2>$null | Select-Object -First 1)
    Write-Host "codex --version: $activeVersion"
}
catch {
    Write-Host "Warning: could not run '$CodexCommand --version': $($_.Exception.Message)"
}
Write-Host "Start a new Codex CLI session, then open / and /model for visual verification."
