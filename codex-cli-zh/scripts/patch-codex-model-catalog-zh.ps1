[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$CatalogPath = "",
    [string]$ConfigPath = "",
    [string]$MapFile = "",
    [string]$BackupDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Resolve-UserHomeDirectory {
    $candidates = @(
        $env:USERPROFILE,
        $env:HOME,
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            return [System.IO.Path]::GetFullPath(
                [System.Environment]::ExpandEnvironmentVariables([string]$candidate)
            )
        }
    }

    throw "Could not resolve the user home directory from USERPROFILE, HOME, or .NET."
}

$script:UserHomeDirectory = Resolve-UserHomeDirectory

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:UserHomeDirectory ".codex/config.toml"
}
if (-not $MapFile) {
    $MapFile = Join-Path $PSScriptRoot "deep-translations.zh.json"
}
if (-not $BackupDirectory) {
    $BackupDirectory = Join-Path $script:UserHomeDirectory ".codex/backups/model-catalog-zh"
}

function Write-Step {
    param([string]$Name)
    Write-Host ""
    Write-Host "== $Name =="
}

function Count-Occurrences {
    param(
        [string]$Text,
        [string]$Needle
    )

    if ([string]::IsNullOrEmpty($Needle)) {
        return 0
    }

    $count = 0
    $index = 0
    while ($true) {
        $index = $Text.IndexOf($Needle, $index, [System.StringComparison]::Ordinal)
        if ($index -lt 0) {
            break
        }
        $count += 1
        $index += $Needle.Length
    }
    return $count
}

function Test-HasUnescapedDoubleQuote {
    param([string]$Text)

    $quote = [char]34
    $slash = [char]92

    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -ne $quote) {
            continue
        }

        $slashCount = 0
        for ($j = $i - 1; $j -ge 0 -and $Text[$j] -eq $slash; $j--) {
            $slashCount += 1
        }

        if (($slashCount % 2) -eq 0) {
            return $true
        }
    }

    return $false
}

function Get-JsonSourceToken {
    param([string]$Text)
    return '"' + $Text + '"'
}

function Resolve-CatalogFile {
    param(
        [string]$RequestedPath,
        [string]$RequestedConfigPath
    )

    $rawPath = $RequestedPath
    $baseDirectory = (Get-Location).Path

    if (-not $rawPath) {
        if (-not (Test-Path -LiteralPath $RequestedConfigPath)) {
            throw "Codex config file not found: $RequestedConfigPath"
        }

        $resolvedConfig = (Resolve-Path -LiteralPath $RequestedConfigPath -ErrorAction Stop).Path
        $baseDirectory = Split-Path -Parent $resolvedConfig
        $singleQuotedPattern = '^\s*model_catalog_json\s*=\s*''(?<value>[^'']+)''\s*(?:#.*)?$'
        $doubleQuotedPattern = '^\s*model_catalog_json\s*=\s*"(?<value>(?:\\.|[^"])*)"\s*(?:#.*)?$'

        foreach ($line in Get-Content -LiteralPath $resolvedConfig -Encoding UTF8) {
            if ($line -match $singleQuotedPattern) {
                $rawPath = [string]$Matches.value
                break
            }
            if ($line -match $doubleQuotedPattern) {
                $jsonLiteral = '"' + [string]$Matches.value + '"'
                $rawPath = [string]($jsonLiteral | ConvertFrom-Json)
                break
            }
        }

        if (-not $rawPath) {
            throw "model_catalog_json is not configured in: $resolvedConfig"
        }
    }

    $expanded = [System.Environment]::ExpandEnvironmentVariables($rawPath)
    if ($expanded -eq "~") {
        $expanded = $script:UserHomeDirectory
    }
    elseif ($expanded.StartsWith("~\") -or $expanded.StartsWith("~/")) {
        $expanded = Join-Path $script:UserHomeDirectory $expanded.Substring(2)
    }
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $baseDirectory $expanded
    }

    $fullPath = [System.IO.Path]::GetFullPath($expanded)
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Model catalog file not found: $fullPath"
    }

    return (Resolve-Path -LiteralPath $fullPath -ErrorAction Stop).Path
}

function Read-ModelCatalogTranslations {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Translation map not found: $Path"
    }

    $map = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $targets = @(
        $map.targets |
            Where-Object { ([string]$_.path -replace "\\", "/") -eq "codex-rs/models-manager/models.json" }
    )
    if ($targets.Count -ne 1) {
        throw "Expected exactly one codex-rs/models-manager/models.json target in: $Path"
    }

    $replacements = @($targets[0].replacements)
    if ($replacements.Count -eq 0) {
        throw "The models.json target contains no replacements: $Path"
    }

    $duplicates = @(
        $replacements |
            Group-Object { [string]$_.from } |
            Where-Object { $_.Count -gt 1 }
    )
    if ($duplicates.Count -gt 0) {
        throw "Duplicate model catalog source mapping: $($duplicates[0].Name)"
    }

    foreach ($item in $replacements) {
        if ($null -eq $item.from -or "" -eq [string]$item.from -or $null -eq $item.to) {
            throw "Each model catalog replacement must contain non-empty 'from' and a 'to' field."
        }
        if (Test-HasUnescapedDoubleQuote -Text ([string]$item.from)) {
            throw "Model catalog replacement 'from' contains an unescaped ASCII double quote: $($item.from)"
        }
        if (Test-HasUnescapedDoubleQuote -Text ([string]$item.to)) {
            throw "Model catalog replacement 'to' contains an unescaped ASCII double quote: $($item.from)"
        }
    }

    return @(
        $replacements |
            Sort-Object `
                @{ Expression = { ([string]$_.from).Length }; Descending = $true },
                @{ Expression = { [string]$_.from }; Descending = $false }
    )
}

$resolvedCatalog = Resolve-CatalogFile -RequestedPath $CatalogPath -RequestedConfigPath $ConfigPath
$resolvedMap = (Resolve-Path -LiteralPath $MapFile -ErrorAction Stop).Path
$replacements = @(Read-ModelCatalogTranslations -Path $resolvedMap)
$original = Get-Content -LiteralPath $resolvedCatalog -Raw -Encoding UTF8

try {
    $null = $original | ConvertFrom-Json
}
catch {
    throw "Model catalog is not valid JSON before patching: $resolvedCatalog`n$($_.Exception.Message)"
}

$patched = $original
$plannedOccurrences = 0
$alreadyTranslated = 0
$absentMappings = 0

foreach ($item in $replacements) {
    $fromToken = Get-JsonSourceToken -Text ([string]$item.from)
    $toToken = Get-JsonSourceToken -Text ([string]$item.to)
    $fromCount = Count-Occurrences -Text $patched -Needle $fromToken
    if ($fromCount -gt 0) {
        $patched = $patched.Replace($fromToken, $toToken)
        $plannedOccurrences += $fromCount
        continue
    }

    $toCount = Count-Occurrences -Text $patched -Needle $toToken
    if ($toCount -gt 0) {
        $alreadyTranslated += $toCount
    }
    else {
        $absentMappings += 1
    }
}

Write-Step "Model catalog translation"
Write-Host "Catalog:       $resolvedCatalog"
Write-Host "Map:           $resolvedMap"
Write-Host "Mappings:      $($replacements.Count)"
Write-Host "Planned:       $plannedOccurrences occurrence(s)"
Write-Host "Already:       $alreadyTranslated occurrence(s)"
Write-Host "Absent:        $absentMappings mapping(s)"

if ($DryRun) {
    Write-Host "Dry run complete. No catalog or backup files were changed."
    return
}

if ($plannedOccurrences -eq 0) {
    Write-Host "Catalog is already translated or contains no mapped UI descriptions. No files were changed."
    return
}

try {
    $null = $patched | ConvertFrom-Json
}
catch {
    throw "Patched model catalog would not be valid JSON. No files were changed.`n$($_.Exception.Message)"
}

$resolvedBackupDirectory = [System.IO.Path]::GetFullPath(
    [System.Environment]::ExpandEnvironmentVariables($BackupDirectory)
)
New-Item -ItemType Directory -Force -Path $resolvedBackupDirectory | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$backupName = "{0}.{1}.bak" -f ([System.IO.Path]::GetFileName($resolvedCatalog)), $timestamp
$backupPath = Join-Path $resolvedBackupDirectory $backupName
Copy-Item -LiteralPath $resolvedCatalog -Destination $backupPath

try {
    [System.IO.File]::WriteAllText(
        $resolvedCatalog,
        $patched,
        [System.Text.UTF8Encoding]::new($false)
    )
    $written = Get-Content -LiteralPath $resolvedCatalog -Raw -Encoding UTF8
    $null = $written | ConvertFrom-Json
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $resolvedCatalog -Force
    throw "Model catalog update failed and the backup was restored: $($_.Exception.Message)"
}

Write-Host "Changed:       $plannedOccurrences occurrence(s)"
Write-Host "Backup:        $backupPath"
Write-Host "Updated:       $resolvedCatalog"
Write-Host "Restart Codex in a new session to load the translated catalog."
