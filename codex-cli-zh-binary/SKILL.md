---
name: codex-cli-zh-binary
description: Install or restore a prebuilt Chinese-localized OpenAI Codex CLI binary by precisely patching the active npm codex wrapper. Use when Codex needs a no-build Windows CLI localization install, needs to switch the current `codex` command to a compiled Chinese `codex.exe`, needs to recover after `npm install -g @openai/codex` overwrote the wrapper, needs to restore the official wrapper backup, or the user asks to 安装中文 Codex CLI / 替换当前 codex 为中文版 / npm 更新后恢复汉化.
---

# Codex CLI 中文二进制替换

## 作用

只用于 Windows 上通过 npm 安装的 Codex CLI。不要用它修改 Codex Desktop、MSIX 包、CC Switch 或 Claude 配置。

这个技能不重新编译源码。它安装已经编译好的中文 `codex.exe`，再精准修改当前 `codex` 命令对应的 npm wrapper，让新开的 Codex CLI 启动这个中文二进制。

## 安装

优先运行脚本。脚本会用 `Get-Command` 解析当前终端实际会执行的 `codex`，找到匹配的 npm wrapper，备份 `codex.js`，然后写入带标记的 override。

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1"
```

如果已有本地编译好的二进制，直接指定路径：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -BinaryPath "D:\path\to\codex.exe"
```

只预览将要修改的 wrapper、安装目录和备份目录，不落盘：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -DryRun
```

## 识别当前 Codex

脚本必须从当前 PATH 可见的命令反推出要修改的 wrapper：

1. 运行 `Get-Command codex -All`。
2. 使用第一个可解析的命令入口，例如 `%APPDATA%\npm\codex.ps1` 或 `%APPDATA%\npm\codex.cmd`。
3. 从这个 shim 所在目录反推 `..\node_modules\@openai\codex\bin\codex.js`。
4. 确认 `codex.js` 里存在 `findCodexExecutable` 后才允许修改。

不要硬编码 `C:\Users\Administrator`、`%APPDATA%` 或某个 npm prefix。用户有多个 Codex 时，默认只修改 `Get-Command` 解析到的第一个 `codex`；如果用户明确给了 `-WrapperPath`，才修改指定 wrapper。

## 验证

安装后运行：

```powershell
codex --version
rg -n -F "codex-cli-zh-binary" "$env:APPDATA\npm\node_modules\@openai\codex\bin\codex.js"
```

界面验证需要新开一个 Codex CLI，会话里输入 `/`，再打开 `/model`，确认命令说明和模型选择界面已经是中文。

## 恢复

恢复最近一次 wrapper 备份：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -Restore
```

只移除本技能写入的 override，回到官方 `findCodexExecutable()`：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -RemoveOverride
```

## 注意

- `npm install -g @openai/codex` 或 `npm update -g @openai/codex` 可能覆盖 wrapper。更新后重新运行本技能即可。
- 不要覆盖正在运行的 `codex.exe`。脚本会把中文二进制复制到独立目录，再让 wrapper 指向它。
- 在用户确认中文 CLI 能正常启动前，保留 wrapper 备份。
