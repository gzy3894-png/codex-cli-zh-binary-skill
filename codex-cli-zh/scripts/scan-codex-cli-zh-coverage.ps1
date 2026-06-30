[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,
    [switch]$IncludeTests,
    [switch]$FailOnFindings
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Resolve-CodexRsRoot {
    param([string]$Root)

    $resolved = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
    $candidate = Join-Path $resolved "codex-rs"
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    }
    if (Test-Path -LiteralPath (Join-Path $resolved "tui\src")) {
        return $resolved
    }
    throw "Could not find codex-rs from SourceRoot: $Root"
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Normalize-Newlines {
    param([string]$Text)
    return $Text -replace "`r`n", "`n"
}

function Get-RelativePath {
    param(
        [string]$Root,
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    return $resolved.Substring($Root.Length).TrimStart("\", "/")
}

function Count-QuotedLiteralOccurrences {
    param(
        [string]$Text,
        [string]$Needle
    )

    $sourceText = Normalize-Newlines -Text $Text
    $sourceNeedle = '"' + (Normalize-Newlines -Text $Needle) + '"'
    return Count-Occurrences -Text $sourceText -Needle $sourceNeedle
}

function Resolve-TargetFile {
    param(
        [string]$CodexRsRoot,
        [string]$RelativePath
    )

    $normalized = $RelativePath -replace "/", "\"
    if ($normalized.StartsWith("codex-rs\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring("codex-rs\".Length)
    }

    $candidate = Join-Path $CodexRsRoot $normalized
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Target file not found for map path '$RelativePath': $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
}

function Find-StringLiteralHits {
    param(
        [string]$Path,
        [string]$Needle
    )

    $hits = @()
    $literalPattern = [regex]'"(?:\\.|[^"\\])*"'
    $lineNumber = 0
    $pendingCfgTest = $false
    $insideTestModule = $false
    $testModuleDepth = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $lineNumber += 1
        if (-not $IncludeTests) {
            if ($insideTestModule) {
                $testModuleDepth += [regex]::Matches($line, "\{").Count
                $testModuleDepth -= [regex]::Matches($line, "\}").Count
                if ($testModuleDepth -le 0) {
                    $insideTestModule = $false
                }
                continue
            }

            if ($line -match "^\s*#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]") {
                $pendingCfgTest = $true
                continue
            }

            if ($pendingCfgTest) {
                if ($line -match "\bmod\s+tests\b") {
                    $testModuleDepth = [regex]::Matches($line, "\{").Count - [regex]::Matches($line, "\}").Count
                    if ($testModuleDepth -le 0) {
                        $testModuleDepth = 1
                    }
                    $insideTestModule = $true
                    $pendingCfgTest = $false
                    continue
                }
                if ($line.Trim() -ne "" -and -not ($line.TrimStart().StartsWith("#"))) {
                    $pendingCfgTest = $false
                }
            }
        }
        $commentIndex = $line.IndexOf("//", [System.StringComparison]::Ordinal)
        foreach ($match in $literalPattern.Matches($line)) {
            if ($commentIndex -ge 0 -and $commentIndex -lt $match.Index) {
                continue
            }
            if ($match.Value.Contains($Needle)) {
                $hits += [pscustomobject]@{
                    Path = $Path
                    Line = $lineNumber
                    Literal = $match.Value
                }
            }
        }
    }

    return $hits
}

function Find-PlainTextHits {
    param(
        [string]$Path,
        [string]$Needle
    )

    $hits = @()
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $lineNumber += 1
        if ($line.Contains($Needle)) {
            $hits += [pscustomobject]@{
                Path = $Path
                Line = $lineNumber
                Literal = $line
            }
        }
    }

    return $hits
}

$codexRs = Resolve-CodexRsRoot -Root $SourceRoot
$tuiSrc = Join-Path $codexRs "tui\src"
if (-not (Test-Path -LiteralPath $tuiSrc)) {
    throw "Could not find TUI source directory: $tuiSrc"
}

$rsFiles = Get-ChildItem -LiteralPath $tuiSrc -Recurse -Filter "*.rs"
if (-not $IncludeTests) {
    $rsFiles = $rsFiles | Where-Object {
        $_.FullName -notmatch "\\tests\\" -and
        $_.Name -ne "tests.rs" -and
        $_.Name -notlike "*_tests.rs"
    }
}
$sourceFiles = @($rsFiles)
$modelsFile = Join-Path $codexRs "models-manager\models.json"
if (Test-Path -LiteralPath $modelsFile) {
    $sourceFiles += Get-Item -LiteralPath $modelsFile
}
$tooltipsFile = Join-Path $codexRs "tui\tooltips.txt"
if (Test-Path -LiteralPath $tooltipsFile) {
    $sourceFiles += Get-Item -LiteralPath $tooltipsFile
}

$sentinels = @(
    "Select Model and Effort",
    "Select Model",
    "To get started",
    "choose what model and reasoning effort to use",
    "Frontier model for complex coding",
    "Reasoning Effort",
    "Current model",
    "Working directory",
    "Approval policy",
    "Use /compact when the conversation gets long",
    "Use /permissions to control when Codex asks for confirmation.",
    'You can resume a previous conversation by running `codex resume`',
    "Paste an image with Ctrl+V to attach it to your next message."
)

Write-Host "Source: $codexRs"
Write-Host "Rust files scanned: $($rsFiles.Count)"
Write-Host "Additional files scanned: $($sourceFiles.Count - $rsFiles.Count)"

$fileTexts = @()
foreach ($file in $sourceFiles) {
    $fileTexts += [pscustomobject]@{
        file = $file
        text = [System.IO.File]::ReadAllText($file.FullName)
    }
}

Write-Host ""
Write-Host "== Likely visible English sentinels =="

$findings = @()
foreach ($text in $sentinels) {
    $hits = @()
    foreach ($file in $sourceFiles) {
        if ($file.Extension -eq ".rs") {
            $hits += Find-StringLiteralHits -Path $file.FullName -Needle $text
        }
        else {
            $hits += Find-PlainTextHits -Path $file.FullName -Needle $text
        }
    }
    foreach ($hit in $hits) {
        $rel = Get-RelativePath -Root $codexRs -Path $hit.Path
        $findings += [pscustomobject]@{
            kind = "sentinel"
            text = $text
            path = $rel
            line = $hit.Line
        }
        Write-Host ("HIT {0}:{1} :: {2}" -f $rel, $hit.Line, $text)
    }
}

if ($findings.Count -eq 0) {
    Write-Host "No sentinel strings found."
}

Write-Host ""
Write-Host "== Bundled map status =="

$slashMapPath = Join-Path $PSScriptRoot "slash-command-translations.zh.json"
$deepMapPath = Join-Path $PSScriptRoot "deep-translations.zh.json"
$slashMap = Read-JsonFile -Path $slashMapPath
$deepMap = Read-JsonFile -Path $deepMapPath

$deepReplacements = @()
foreach ($target in $deepMap.targets) {
    foreach ($replacement in $target.replacements) {
        $deepReplacements += $replacement
    }
}

Write-Host "Slash replacements: $($slashMap.Count)"
Write-Host "Deep replacements:  $($deepReplacements.Count)"

$mappedEnglishStillPresent = 0
$mappedFindings = @()
$slashSource = Join-Path $tuiSrc "slash_command.rs"
$slashText = [System.IO.File]::ReadAllText($slashSource)
foreach ($item in $slashMap) {
    $count = Count-QuotedLiteralOccurrences -Text $slashText -Needle ([string]$item.from)
    if ($count -gt 0) {
        $mappedEnglishStillPresent += $count
        $mappedFindings += [pscustomobject]@{
            path = "tui\src\slash_command.rs"
            text = [string]$item.from
            count = $count
        }
    }
}
foreach ($target in $deepMap.targets) {
    $targetFile = Resolve-TargetFile -CodexRsRoot $codexRs -RelativePath ([string]$target.path)
    $targetText = [System.IO.File]::ReadAllText($targetFile)
    $targetExtension = [System.IO.Path]::GetExtension($targetFile)
    $relativeTarget = Get-RelativePath -Root $codexRs -Path $targetFile
    foreach ($item in $target.replacements) {
        if ($targetExtension -eq ".rs" -or $targetExtension -eq ".json") {
            $count = Count-QuotedLiteralOccurrences -Text $targetText -Needle ([string]$item.from)
        }
        else {
            $count = Count-Occurrences -Text (Normalize-Newlines -Text $targetText) -Needle (Normalize-Newlines -Text ([string]$item.from))
        }
        if ($count -gt 0) {
            $mappedEnglishStillPresent += $count
            $mappedFindings += [pscustomobject]@{
                path = $relativeTarget
                text = [string]$item.from
                count = $count
            }
        }
    }
}

Write-Host "Mapped English quoted occurrences still present: $mappedEnglishStillPresent"
foreach ($finding in ($mappedFindings | Select-Object -First 20)) {
    Write-Host ("MAPPED {0}x {1} :: {2}" -f $finding.count, $finding.path, $finding.text)
}

if ($FailOnFindings -and ($findings.Count -gt 0 -or $mappedEnglishStillPresent -gt 0)) {
    throw "Coverage scan found visible English or mapped English still present."
}
