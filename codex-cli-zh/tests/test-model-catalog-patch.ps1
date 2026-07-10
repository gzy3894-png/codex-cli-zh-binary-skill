[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Invoke-CatalogPatch {
    param([string[]]$Arguments)

    $output = @(& $script:PowerShellExe @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Catalog patch command failed with exit code ${exitCode}:`n$($output -join "`n")"
    }
    return $output
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$patchScript = Join-Path $skillRoot "scripts\patch-codex-model-catalog-zh.ps1"
$mapFile = Join-Path $skillRoot "scripts\deep-translations.zh.json"

if (-not (Test-Path -LiteralPath $patchScript)) {
    throw "Missing patch script: $patchScript"
}
if (-not (Test-Path -LiteralPath $mapFile)) {
    throw "Missing translation map: $mapFile"
}

$translationMap = Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
$modelTargets = @(
    $translationMap.targets |
        Where-Object { ([string]$_.path -replace "\\", "/") -eq "codex-rs/models-manager/models.json" }
)
if ($modelTargets.Count -ne 1) {
    throw "Expected exactly one models.json translation target in: $mapFile"
}
$translations = @($modelTargets[0].replacements)

function Get-ExpectedTranslation {
    param([string]$English)

    $matches = @($translations | Where-Object { [string]$_.from -eq $English })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one mapping for: $English"
    }
    return [string]$matches[0].to
}

$script:PowerShellExe = ""
foreach ($name in @("pwsh", "powershell")) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $script:PowerShellExe = $command.Source
        break
    }
}
if (-not $script:PowerShellExe) {
    throw "Neither pwsh nor powershell is available for the fixture test."
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("codex-cli-zh-model-catalog-test-" + [guid]::NewGuid().ToString("N"))
$catalogPath = Join-Path $tempRoot "catalog.json"
$backupDirectory = Join-Path $tempRoot "backups"
$portableHome = Join-Path $tempRoot "home"
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    New-Item -ItemType Directory -Force -Path $portableHome | Out-Null
    Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue
    $env:HOME = $portableHome

    $fixture = @'
{
  "models": [
    {
      "slug": "gpt-5.6-sol",
      "description": "Latest frontier agentic coding model.",
      "supported_reasoning_levels": [
        {
          "effort": "low",
          "description": "Fast responses with lighter reasoning"
        },
        {
          "effort": "ultra",
          "description": "Maximum reasoning with automatic task delegation"
        }
      ],
      "additional_speed_tiers": [
        {
          "name": "Fast",
          "description": "1.5x speed, increased usage"
        }
      ],
      "unrelated": "keep me"
    },
    {
      "slug": "gpt-5.4",
      "description": "Strong model for everyday coding.",
      "supported_reasoning_levels": [
        {
          "effort": "medium",
          "description": "Balances speed and reasoning depth for everyday tasks"
        }
      ]
    }
  ]
}
'@
    $fixture = $fixture -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText(
        $catalogPath,
        $fixture,
        [System.Text.UTF8Encoding]::new($false)
    )

    $originalHash = Get-FileSha256 -Path $catalogPath

    Invoke-CatalogPatch -Arguments @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $patchScript,
        "-CatalogPath",
        $catalogPath,
        "-MapFile",
        $mapFile,
        "-BackupDirectory",
        $backupDirectory,
        "-DryRun"
    ) | Out-Null

    Assert-True -Condition ((Get-FileSha256 -Path $catalogPath) -eq $originalHash) -Message "DryRun changed the catalog."
    Assert-True -Condition (-not (Test-Path -LiteralPath $backupDirectory)) -Message "DryRun created a backup directory."

    Invoke-CatalogPatch -Arguments @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $patchScript,
        "-CatalogPath",
        $catalogPath,
        "-MapFile",
        $mapFile,
        "-BackupDirectory",
        $backupDirectory
    ) | Out-Null

    $patchedRaw = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8
    $patched = $patchedRaw | ConvertFrom-Json
    $sol = @($patched.models | Where-Object { $_.slug -eq "gpt-5.6-sol" })[0]
    $gpt54 = @($patched.models | Where-Object { $_.slug -eq "gpt-5.4" })[0]

    Assert-True -Condition ($sol.description -eq (Get-ExpectedTranslation -English "Latest frontier agentic coding model.")) -Message "Model description was not translated."
    Assert-True -Condition ($sol.supported_reasoning_levels[0].description -eq (Get-ExpectedTranslation -English "Fast responses with lighter reasoning")) -Message "Low reasoning description was not translated."
    Assert-True -Condition ($sol.supported_reasoning_levels[1].description -eq (Get-ExpectedTranslation -English "Maximum reasoning with automatic task delegation")) -Message "Ultra reasoning description was not translated."
    Assert-True -Condition ($sol.additional_speed_tiers[0].name -eq (Get-ExpectedTranslation -English "Fast")) -Message "Speed tier name was not translated."
    Assert-True -Condition ($sol.additional_speed_tiers[0].description -eq (Get-ExpectedTranslation -English "1.5x speed, increased usage")) -Message "Speed tier description was not translated."
    Assert-True -Condition ($sol.unrelated -eq "keep me") -Message "Unmapped content changed."
    Assert-True -Condition ($gpt54.description -eq (Get-ExpectedTranslation -English "Strong model for everyday coding.")) -Message "Existing mapped model description was not translated."
    Assert-True -Condition ($gpt54.supported_reasoning_levels[0].description -eq (Get-ExpectedTranslation -English "Balances speed and reasoning depth for everyday tasks")) -Message "Medium reasoning description was not translated."
    Assert-True -Condition ($patchedRaw.Contains("`r`n")) -Message "CRLF line endings were not preserved."

    $patchedBytes = [System.IO.File]::ReadAllBytes($catalogPath)
    $hasBom = $patchedBytes.Length -ge 3 -and $patchedBytes[0] -eq 0xEF -and $patchedBytes[1] -eq 0xBB -and $patchedBytes[2] -eq 0xBF
    Assert-True -Condition (-not $hasBom) -Message "UTF-8 BOM was added."

    $backups = @(Get-ChildItem -LiteralPath $backupDirectory -File)
    Assert-True -Condition ($backups.Count -eq 1) -Message "Expected exactly one backup after the first mutation."
    Assert-True -Condition ((Get-FileSha256 -Path $backups[0].FullName) -eq $originalHash) -Message "Backup does not match the original catalog."

    $patchedHash = Get-FileSha256 -Path $catalogPath
    Invoke-CatalogPatch -Arguments @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $patchScript,
        "-CatalogPath",
        $catalogPath,
        "-MapFile",
        $mapFile,
        "-BackupDirectory",
        $backupDirectory
    ) | Out-Null

    Assert-True -Condition ((Get-FileSha256 -Path $catalogPath) -eq $patchedHash) -Message "Second run was not idempotent."
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $backupDirectory -File).Count -eq 1) -Message "Idempotent run created another backup."

    Write-Host "PASS: model catalog patch dry-run, mutation, backup, encoding, and idempotency"
}
finally {
    if ($null -eq $originalUserProfile) {
        Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue
    }
    else {
        $env:USERPROFILE = $originalUserProfile
    }
    if ($null -eq $originalHome) {
        Remove-Item Env:HOME -ErrorAction SilentlyContinue
    }
    else {
        $env:HOME = $originalHome
    }

    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $safePrefix = $tempBase.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
    $safeLeaf = Split-Path -Leaf $resolvedTempRoot
    if (
        $resolvedTempRoot.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        $safeLeaf.StartsWith("codex-cli-zh-model-catalog-test-", [System.StringComparison]::Ordinal)
    ) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
