---
name: codex-cli-zh-binary
description: Install, switch, verify, or restore a prebuilt Chinese-localized OpenAI Codex CLI binary on Windows by patching only the active npm `codex` wrapper. Use when the user wants a no-build Chinese Codex CLI, asks to replace the current `codex` command with a localized `codex.exe`, needs to reapply localization after `npm install -g @openai/codex`, or needs to restore/remove this wrapper override. Triggers include 安装中文 Codex CLI, codex汉化项目, Codex CLI 汉化项目, Codex CLI 中文汉化, Codex 中文版, 替换当前 codex 为中文版, npm 更新后恢复汉化.
---

# Codex CLI 中文二进制替换

## 适用范围

只用于 Windows 上通过 npm 安装的 Codex CLI。不要用它修改 Codex Desktop、MSIX 包、CC Switch、Claude 配置或用户的 `config.toml`。

这个技能不重新编译源码。它安装已经编译好的中文 `codex.exe`，再精确修改当前 `codex` 命令对应的 npm wrapper，让新开的 Codex CLI 启动这个中文二进制。

## 工作方式

按下面的顺序处理，除非用户明确给出 `-WrapperPath`、`-BinaryPath` 或其他脚本参数：

1. 用 `Get-Command codex -All` 解析当前终端实际会执行的 `codex`。
2. 从命令入口反推 npm wrapper：`node_modules\@openai\codex\bin\codex.js`。
3. 确认 wrapper 里存在 `findCodexExecutable`，避免修改未知文件。
4. 下载或复制中文 `codex.exe` 到独立安装目录。
5. 备份原始 `codex.js`，写入带 `codex-cli-zh-binary` 标记的 override。
6. 如果中文二进制不存在，override 必须回退到官方 `findCodexExecutable()`。

## 安装

优先运行脚本：

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
