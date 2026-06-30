[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Install,
    [switch]$UseWrapperOverride,
    [string]$SourceRoot = "",
    [string]$MapFile = "",
    [string]$CargoTargetDir = "E:\cz\target-zh-deep",
    [string]$CargoHome = "E:\cz\cargo-home",
    [string]$PythonExe = "E:\tools\python\python.exe",
    [string]$BuiltExe = "",
    [string]$TargetExe = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if (-not $MapFile) {
    $MapFile = Join-Path $PSScriptRoot "deep-translations.zh.json"
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message"
}

function Normalize-Newlines {
    param([string]$Text)
    return $Text -replace "`r`n", "`n"
}

function Restore-Newlines {
    param(
        [string]$Text,
        [string]$LineEnding
    )

    if ($LineEnding -eq "`r`n") {
        return $Text -replace "`n", "`r`n"
    }

    return $Text
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

function Resolve-SourceLayout {
    param([string]$Root)

    if (-not $Root) {
        throw "Pass -SourceRoot. It can be the repo root containing codex-rs or the codex-rs directory."
    }

    $rootPath = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
    $repoCandidate = Join-Path $rootPath "codex-rs\tui\src"
    $rsCandidate = Join-Path $rootPath "tui\src"

    if (Test-Path -LiteralPath $repoCandidate) {
        return [pscustomobject]@{
            RepoRoot = $rootPath
            CodexRsRoot = (Join-Path $rootPath "codex-rs")
            PathMode = "repo"
        }
    }

    if (Test-Path -LiteralPath $rsCandidate) {
        return [pscustomobject]@{
            RepoRoot = (Split-Path -Parent $rootPath)
            CodexRsRoot = $rootPath
            PathMode = "codex-rs"
        }
    }

    throw "Could not find codex-rs TUI source under: $Root"
}

function Resolve-TargetFile {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $normalized = $RelativePath -replace "/", "\"
    if ($normalized.StartsWith("codex-rs\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $withoutPrefix = $normalized.Substring("codex-rs\".Length)
        $candidate = Join-Path $Layout.CodexRsRoot $withoutPrefix
    }
    else {
        $candidate = Join-Path $Layout.CodexRsRoot $normalized
    }

    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Target file not found for map path '$RelativePath': $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
}

function Read-TranslationMap {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Translation map not found: $Path"
    }

    $map = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $map.targets) {
        throw "Translation map must contain a 'targets' array."
    }

    foreach ($target in @($map.targets)) {
        if (-not $target.path) {
            throw "Each target must contain a non-empty path."
        }
        if (-not $target.replacements) {
            throw "Target '$($target.path)' must contain replacements."
        }
        foreach ($item in @($target.replacements)) {
            if ($null -eq $item.from -or "" -eq [string]$item.from -or $null -eq $item.to) {
                throw "Each replacement in '$($target.path)' must contain non-empty 'from' and a 'to' field."
            }
            if (Test-HasUnescapedDoubleQuote -Text ([string]$item.from)) {
                throw "Replacement 'from' in '$($target.path)' contains an unescaped ASCII double quote. Escape ASCII quotes as backslash-quote in source literal text, or avoid ASCII quotes."
            }
            if (Test-HasUnescapedDoubleQuote -Text ([string]$item.to)) {
                throw "Replacement 'to' in '$($target.path)' contains an unescaped ASCII double quote. Escape ASCII quotes as backslash-quote in source literal text, or prefer Chinese quotes."
            }
        }
    }

    return $map
}

function Get-SortedReplacements {
    param([object[]]$Replacements)

    return @(
        $Replacements |
            Sort-Object `
                @{ Expression = { ([string]$_.from).Length }; Descending = $true },
                @{ Expression = { [string]$_.from }; Descending = $false }
    )
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

function Get-SourceLiteral {
    param([string]$Text)

    return '"' + $Text + '"'
}

function Uses-QuotedSourceLiteral {
    param([string]$FilePath)

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    return @(".rs", ".json") -contains $extension
}

function Get-SourceNeedle {
    param(
        [string]$FilePath,
        [string]$Text
    )

    if (Uses-QuotedSourceLiteral -FilePath $FilePath) {
        return Get-SourceLiteral -Text $Text
    }

    return $Text
}

function Get-RustRawSourceLiteral {
    param([string]$Text)

    $rawText = $Text.Replace('\"', '"')
    return 'r#"' + $rawText + '"#'
}

function Get-SourceNeedles {
    param(
        [string]$FilePath,
        [string]$Text
    )

    $needles = New-Object System.Collections.Generic.List[string]
    $needles.Add((Get-SourceNeedle -FilePath $FilePath -Text $Text))

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($extension -eq ".rs") {
        $needles.Add((Get-RustRawSourceLiteral -Text $Text))
    }

    return @($needles | Select-Object -Unique)
}

function Test-TargetPatch {
    param(
        [string]$FilePath,
        [object[]]$Replacements
    )

    $contentRaw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $lineEnding = if ($contentRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = Normalize-Newlines -Text $contentRaw
    $missing = New-Object System.Collections.Generic.List[string]
    $plannedOccurrences = 0
    $already = 0

    foreach ($item in (Get-SortedReplacements -Replacements $Replacements)) {
        $from = Normalize-Newlines -Text ([string]$item.from)
        $to = Normalize-Newlines -Text ([string]$item.to)
        $sourceFromNeedles = Get-SourceNeedles -FilePath $FilePath -Text $from
        $sourceToNeedles = Get-SourceNeedles -FilePath $FilePath -Text $to
        $count = 0
        foreach ($sourceFrom in $sourceFromNeedles) {
            $count += [regex]::Matches($content, [regex]::Escape($sourceFrom)).Count
        }
        if ($count -gt 0) {
            $plannedOccurrences += $count
        }
        else {
            $alreadyPresent = $false
            foreach ($sourceTo in $sourceToNeedles) {
                if ($content.Contains($sourceTo)) {
                    $alreadyPresent = $true
                    break
                }
            }
            if ($alreadyPresent) {
                $already += 1
            }
            else {
                $missing.Add($from)
            }
        }
    }

    return [pscustomobject]@{
        PlannedOccurrences = $plannedOccurrences
        AlreadyTranslated = $already
        Missing = $missing
    }
}

function Apply-TargetPatch {
    param(
        [string]$FilePath,
        [object[]]$Replacements
    )

    $contentRaw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $lineEnding = if ($contentRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = Normalize-Newlines -Text $contentRaw
    $check = Test-TargetPatch -FilePath $FilePath -Replacements $Replacements
    if ($check.Missing.Count -gt 0) {
        $sample = ($check.Missing | Select-Object -First 10) -join "`n  - "
        throw "Some expected English strings were not found and are not already translated in ${FilePath}:`n  - $sample"
    }

    $changed = 0
    foreach ($item in (Get-SortedReplacements -Replacements $Replacements)) {
        $from = Normalize-Newlines -Text ([string]$item.from)
        $to = Normalize-Newlines -Text ([string]$item.to)
        $sourceFromNeedles = Get-SourceNeedles -FilePath $FilePath -Text $from
        $sourceTo = Get-SourceNeedle -FilePath $FilePath -Text $to
        foreach ($sourceFrom in $sourceFromNeedles) {
            $count = [regex]::Matches($content, [regex]::Escape($sourceFrom)).Count
            if ($count -gt 0) {
                $content = $content.Replace($sourceFrom, $sourceTo)
                $changed += $count
            }
        }
    }

    if ($changed -gt 0) {
        $content = Restore-Newlines -Text $content -LineEnding $lineEnding
        [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.UTF8Encoding]::new($false))
    }

    return [pscustomobject]@{
        ChangedOccurrences = $changed
        AlreadyTranslated = $check.AlreadyTranslated
    }
}

function Apply-KeymapActionLabelPatch {
    param([string]$CodexRsRoot)

    $file = Join-Path $CodexRsRoot "tui\src\keymap_setup\actions.rs"
    if (-not (Test-Path -LiteralPath $file)) {
        return [pscustomobject]@{
            Changed = $false
            Already = $false
            File = $file
        }
    }

    $contentRaw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $lineEnding = if ($contentRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = Normalize-Newlines -Text $contentRaw
    if ($content.Contains("fn zh_action_label(action: &str) -> Option<&'static str>")) {
        return [pscustomobject]@{
            Changed = $false
            Already = $true
            File = $file
        }
    }

    $needle = @'
pub(super) fn action_label(action: &str) -> String {
    action
        .split('_')
'@
    $replacement = @'
pub(super) fn action_label(action: &str) -> String {
    if let Some(label) = zh_action_label(action) {
        return label.to_string();
    }

    action
        .split('_')
'@
    if (-not $content.Contains($needle)) {
        throw "Could not find keymap action_label insertion point in $file"
    }
    $content = $content.Replace($needle, $replacement)

    $tailNeedle = @'
        .collect::<Vec<_>>()
        .join(" ")
}
'@
    $tailReplacement = @'
        .collect::<Vec<_>>()
        .join(" ")
}

fn zh_action_label(action: &str) -> Option<&'static str> {
    match action {
        "open_transcript" => Some("打开转录"),
        "open_external_editor" => Some("在外部编辑器打开"),
        "copy" => Some("复制回复"),
        "clear_terminal" => Some("清空终端"),
        "toggle_vim_mode" => Some("切换 Vim 模式"),
        "toggle_fast_mode" => Some("切换快速模式"),
        "toggle_raw_output" => Some("切换原始输出"),
        "interrupt_turn" => Some("中断回合"),
        "decrease_reasoning_effort" => Some("降低推理强度"),
        "increase_reasoning_effort" => Some("提高推理强度"),
        "edit_queued_message" => Some("编辑队列消息"),
        "submit" => Some("提交"),
        "queue" => Some("加入队列"),
        "toggle_shortcuts" => Some("显示或隐藏快捷键"),
        "history_search_previous" => Some("上一个历史匹配"),
        "history_search_next" => Some("下一个历史匹配"),
        "insert_newline" => Some("插入换行"),
        "move_left" => Some("左移"),
        "move_right" => Some("右移"),
        "move_up" => Some("上移"),
        "move_down" => Some("下移"),
        "move_word_left" => Some("左移一个词"),
        "move_word_right" => Some("右移一个词"),
        "move_line_start" => Some("到行首"),
        "move_line_end" => Some("到行尾"),
        "delete_backward" => Some("向左删除"),
        "delete_forward" => Some("向右删除"),
        "delete_backward_word" => Some("删除前一个词"),
        "delete_forward_word" => Some("删除后一个词"),
        "kill_line_start" => Some("删除到行首"),
        "kill_whole_line" => Some("删除整行"),
        "kill_line_end" => Some("删除到行尾"),
        "yank" => Some("粘贴剪切缓冲"),
        "enter_insert" => Some("进入插入模式"),
        "append_after_cursor" => Some("光标后插入"),
        "append_line_end" => Some("行尾插入"),
        "insert_line_start" => Some("行首插入"),
        "open_line_below" => Some("下方新建行"),
        "open_line_above" => Some("上方新建行"),
        "move_word_forward" => Some("到下一个词"),
        "move_word_backward" => Some("到上一个词"),
        "move_word_end" => Some("到词尾"),
        "delete_char" => Some("删除字符"),
        "substitute_char" => Some("替换字符"),
        "delete_to_line_end" => Some("删除到行尾"),
        "change_to_line_end" => Some("修改到行尾"),
        "yank_line" => Some("复制整行"),
        "paste_after" => Some("光标后粘贴"),
        "start_delete_operator" => Some("开始删除操作"),
        "start_yank_operator" => Some("开始复制操作"),
        "start_change_operator" => Some("开始修改操作"),
        "cancel_operator" => Some("取消操作符"),
        "delete_line" => Some("删除整行"),
        "motion_left" => Some("向左移动"),
        "motion_right" => Some("向右移动"),
        "motion_up" => Some("向上移动"),
        "motion_down" => Some("向下移动"),
        "motion_word_forward" => Some("移到下个词"),
        "motion_word_backward" => Some("移到上个词"),
        "motion_word_end" => Some("移到词尾"),
        "motion_line_start" => Some("移到行首"),
        "motion_line_end" => Some("移到行尾"),
        "select_inner_text_object" => Some("选择内部文本对象"),
        "select_around_text_object" => Some("选择周围文本对象"),
        "word" => Some("当前词"),
        "big_word" => Some("当前大词"),
        "parentheses" => Some("圆括号"),
        "brackets" => Some("方括号"),
        "braces" => Some("花括号"),
        "double_quote" => Some("双引号"),
        "single_quote" => Some("单引号"),
        "backtick" => Some("反引号"),
        "scroll_up" => Some("上滚一行"),
        "scroll_down" => Some("下滚一行"),
        "page_up" => Some("上翻一页"),
        "page_down" => Some("下翻一页"),
        "half_page_up" => Some("上翻半页"),
        "half_page_down" => Some("下翻半页"),
        "jump_top" => Some("跳到开头"),
        "jump_bottom" => Some("跳到末尾"),
        "close" => Some("关闭"),
        "close_transcript" => Some("关闭转录"),
        "accept" => Some("接受选择"),
        "cancel" => Some("取消"),
        "open_fullscreen" => Some("打开全屏详情"),
        "open_thread" => Some("打开来源线程"),
        "approve" => Some("批准"),
        "approve_for_session" => Some("本会话批准"),
        "approve_for_prefix" => Some("按前缀批准"),
        "deny" => Some("拒绝"),
        "decline" => Some("拒绝并说明"),
        _ => None,
    }
}
'@
    if (-not $content.Contains($tailNeedle)) {
        throw "Could not find keymap action_label helper insertion point in $file"
    }
    $content = $content.Replace($tailNeedle, $tailReplacement)
    $content = Restore-Newlines -Text $content -LineEnding $lineEnding
    [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        Changed = $true
        Already = $false
        File = $file
    }
}

function Get-CodexVersion {
    try {
        $versionLine = (& codex --version 2>$null | Select-Object -First 1)
        if ($versionLine -match "(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)") {
            return $Matches[1]
        }
    }
    catch {
        return ""
    }
    return ""
}

function Resolve-CodexNativeExe {
    param([string]$RequestedTarget)

    if ($RequestedTarget) {
        return (Resolve-Path -LiteralPath $RequestedTarget -ErrorAction Stop).Path
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

    return ""
}

function Test-ExecutableLockedByProcess {
    param([string]$ExePath)

    if (-not (Test-Path -LiteralPath $ExePath)) {
        return $false
    }

    $resolved = (Resolve-Path -LiteralPath $ExePath -ErrorAction Stop).Path
    $running = @(
        Get-CimInstance Win32_Process -Filter "Name = 'codex.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                ($_.ExecutablePath -ieq $resolved -or $_.CommandLine -match [regex]::Escape($resolved))
            }
    )

    return ($running.Count -gt 0)
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
// codex-cli-zh-deep-patch start
const localWindowsBinaryPath = $jsonPath;
const binaryPath =
  process.platform === "win32" && existsSync(localWindowsBinaryPath)
    ? localWindowsBinaryPath
    : findCodexExecutable();
// codex-cli-zh-deep-patch end
"@

    $deepPattern = "(?s)// codex-cli-zh-deep-patch start.*?// codex-cli-zh-deep-patch end"
    $slashPattern = "(?s)// codex-cli-zh-slash-patch start.*?// codex-cli-zh-slash-patch end"
    $plainPattern = "const binaryPath = findCodexExecutable();"

    if ([regex]::IsMatch($content, $deepPattern)) {
        $content = [regex]::Replace($content, $deepPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $override }, 1)
    }
    elseif ([regex]::IsMatch($content, $slashPattern)) {
        $content = [regex]::Replace($content, $slashPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $override }, 1)
    }
    elseif ($content.Contains($plainPattern)) {
        $content = $content.Replace($plainPattern, $override)
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

Write-Step "Plan"
$version = Get-CodexVersion
Write-Host "Codex version: $(if ($version) { $version } else { 'unknown' })"
Write-Host "Source root:   $(if ($SourceRoot) { $SourceRoot } else { '<required>' })"
Write-Host "Map file:      $MapFile"
Write-Host "Cargo target:  $CargoTargetDir"
Write-Host "Python:        $(if ($PythonExe) { $PythonExe } else { '<unchanged>' })"
Write-Host "Install:       $Install"
Write-Host "Wrapper mode:  $UseWrapperOverride"

Write-Step "Toolchain"
foreach ($tool in @("cargo", "rustc")) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $cmd) {
        if ($DryRun -or $SkipBuild) {
            Write-Host ("{0,-6} not found (required only for build)" -f $tool)
        }
        else {
            throw "Required build tool not found on PATH: $tool"
        }
    }
    else {
        Write-Host ("{0,-6} {1}" -f $tool, $cmd.Source)
    }
}

$map = Read-TranslationMap -Path $MapFile
$layout = Resolve-SourceLayout -Root $SourceRoot
Write-Host "Cargo root:    $($layout.CodexRsRoot)"
Write-Host "Targets:       $(@($map.targets).Count)"

Write-Step "Patch analysis"
$totalPlanned = 0
$totalAlready = 0
$allMissing = New-Object System.Collections.Generic.List[string]

foreach ($target in @($map.targets)) {
    $file = Resolve-TargetFile -Layout $layout -RelativePath ([string]$target.path)
    $check = Test-TargetPatch -FilePath $file -Replacements @($target.replacements)
    $totalPlanned += $check.PlannedOccurrences
    $totalAlready += $check.AlreadyTranslated
    if ($check.Missing.Count -gt 0) {
        foreach ($missing in $check.Missing) {
            $allMissing.Add("$($target.path) :: $missing")
        }
    }
    Write-Host ("{0}: planned={1}, already={2}, missing={3}" -f $target.path, $check.PlannedOccurrences, $check.AlreadyTranslated, $check.Missing.Count)
}

Write-Host "Total planned occurrences: $totalPlanned"
Write-Host "Total already translated:  $totalAlready"

if ($allMissing.Count -gt 0) {
    $sample = ($allMissing | Select-Object -First 12) -join "`n  - "
    throw "Missing strings detected. Update the map for upstream changes before patching:`n  - $sample"
}

if ($DryRun) {
    Write-Step "Dry run complete"
    Write-Host "No source files, build artifacts, or installed binaries were changed."
    exit 0
}

Write-Step "Apply patch"
$totalChanged = 0
foreach ($target in @($map.targets)) {
    $file = Resolve-TargetFile -Layout $layout -RelativePath ([string]$target.path)
    $result = Apply-TargetPatch -FilePath $file -Replacements @($target.replacements)
    $totalChanged += $result.ChangedOccurrences
    Write-Host ("{0}: changed={1}, already={2}" -f $target.path, $result.ChangedOccurrences, $result.AlreadyTranslated)
}
Write-Host "Total changed occurrences: $totalChanged"

$keymapLabelPatch = Apply-KeymapActionLabelPatch -CodexRsRoot $layout.CodexRsRoot
if ($keymapLabelPatch.Changed) {
    Write-Host "codex-rs/tui/src/keymap_setup/actions.rs: keymap action labels patched"
}
elseif ($keymapLabelPatch.Already) {
    Write-Host "codex-rs/tui/src/keymap_setup/actions.rs: keymap action labels already patched"
}

if ($SkipBuild) {
    Write-Step "Skipped build"
    Write-Host "Source files were patched. Re-run without -SkipBuild to rebuild codex.exe."
    exit 0
}

Write-Step "Build"
New-Item -ItemType Directory -Force -Path $CargoHome | Out-Null
New-Item -ItemType Directory -Force -Path $CargoTargetDir | Out-Null
$env:CARGO_HOME = (Resolve-Path -LiteralPath $CargoHome -ErrorAction Stop).Path
$env:CARGO_TARGET_DIR = (Resolve-Path -LiteralPath $CargoTargetDir -ErrorAction Stop).Path
if ($PythonExe) {
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        throw "Configured Python executable not found: $PythonExe"
    }
    $env:PYTHON = (Resolve-Path -LiteralPath $PythonExe -ErrorAction Stop).Path
}
$candidateBuiltExe = Join-Path $env:CARGO_TARGET_DIR "release\codex.exe"
if (Test-ExecutableLockedByProcess -ExePath $candidateBuiltExe) {
    throw "Target codex.exe is currently running and Windows will not let Cargo replace it: $candidateBuiltExe. Use a different -CargoTargetDir, for example E:\cz\target-zh-deep-next."
}
Invoke-Checked -FilePath "cargo" -Arguments @("build", "--release", "-p", "codex-cli") -WorkingDirectory $layout.CodexRsRoot

if (-not $BuiltExe) {
    $BuiltExe = Join-Path $env:CARGO_TARGET_DIR "release\codex.exe"
}
if (-not (Test-Path -LiteralPath $BuiltExe)) {
    throw "Build did not produce codex.exe: $BuiltExe"
}
$BuiltExe = (Resolve-Path -LiteralPath $BuiltExe -ErrorAction Stop).Path
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
    Write-Host "Patched binary is ready but not installed. Re-run with -Install to update the active CLI path."
    exit 0
}

Write-Step "Install"
$backupDir = Join-Path $env:USERPROFILE ".codex\backups\cli-zh-deep"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

if ($UseWrapperOverride) {
    $wrapper = Install-CodexNodeWrapperOverride -NativeExe $BuiltExe -BackupDir $backupDir
    Write-Host "Wrapper:       $($wrapper.WrapperPath)"
    Write-Host "Wrapper backup:$($wrapper.BackupPath)"
    Write-Host "Native exe:    $($wrapper.NativeExe)"
    Write-Host "Restart Codex CLI before checking localized prompts."
    exit 0
}

$target = Resolve-CodexNativeExe -RequestedTarget $TargetExe
if (-not $target) {
    throw "Could not locate installed native codex.exe. Pass -TargetExe or use -UseWrapperOverride."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $backupDir ("codex.exe.$timestamp.bak")
Copy-Item -LiteralPath $target -Destination $backup -Force
Copy-Item -LiteralPath $BuiltExe -Destination $target -Force
Write-Host "Backup:        $backup"
Write-Host "Installed:     $target"
Write-Host "Restart Codex CLI before checking localized prompts."
