# Codex CLI 中文二进制替换技能

这个仓库提供一个 Codex Skill，用预编译的中文 `codex.exe` 接管当前 npm 安装的 Codex CLI wrapper。它适合只想把本机 `codex` 命令切到中文界面、但不想重新编译源码的场景。

它的改动范围刻意保持很小：不改用户配置、不碰 CC Switch、不处理 Codex Desktop，只定位当前终端实际会执行的 npm wrapper，并让新开的 Codex CLI 启动中文二进制。

当前预编译二进制基于 Codex CLI `0.142.2`。本地验证过的 Windows x64 产物信息：

- 版本：`codex-cli 0.142.2`
- SHA256：`EFAF3565534AE16BA48350193F43EE37517F5A9C8E8D8E819B6090977FBCE083`

仓库里只放技能和安装脚本，不把 300MB 级别的 exe 写进 Git 历史。预编译二进制会作为 GitHub Release 资产发布，文件名固定为 `codex-cli-zh-windows-x64.exe`。

## 它怎么工作

Codex CLI 的 npm 包在 Windows 上通常会生成 `codex.ps1` / `codex.cmd` 入口，真正执行时再进入：

```text
%APPDATA%\npm\node_modules\@openai\codex\bin\codex.js
```

这个技能不会盲目扫描全盘，也不会硬编码某个用户目录。脚本会先用 `Get-Command codex -All` 找到当前终端实际会执行的 `codex`，再从这个 shim 反推它所属的 `codex.js`，确认里面有 `findCodexExecutable` 后才写入带标记的 override。

写入后的逻辑大致是：

```javascript
const localWindowsBinaryPath = "已安装的中文 codex.exe";
const binaryPath =
  process.platform === "win32" && existsSync(localWindowsBinaryPath)
    ? localWindowsBinaryPath
    : findCodexExecutable();
```

如果中文二进制不存在，wrapper 会回退到官方解析逻辑。安装前会备份原始 `codex.js`。

## 安装技能

克隆仓库后，把技能目录复制到 Codex 的 skills 目录：

```powershell
git clone https://github.com/gzy3894-png/codex-cli-zh-binary-skill.git
Copy-Item -Recurse -Force .\codex-cli-zh-binary-skill\codex-cli-zh-binary "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary"
```

然后在 Codex 里可以这样说：

```text
使用 $codex-cli-zh-binary 安装中文 Codex CLI
```

也可以直接运行脚本。

## 一键安装

默认从本仓库最新 Release 下载 `codex-cli-zh-windows-x64.exe`，复制到当前用户本地目录，然后修改当前 `codex` wrapper：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1"
```

如果你已经有本地编译好的 `codex.exe`，可以直接指定：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -BinaryPath "D:\path\to\codex.exe"
```

预览将要修改什么，不落盘：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -DryRun
```

默认下载官方 Release 资产时，脚本会校验上面列出的 SHA256。你指定自己的 `-BinaryPath` 时，默认不强制校验；如果需要，也可以传入 `-ExpectedSha256`。

## 验证

安装后运行：

```powershell
codex --version
```

应该看到中文二进制对应的版本，例如：

```text
codex-cli 0.142.2
```

再检查 wrapper 是否有技能标记：

```powershell
rg -n -F "codex-cli-zh-binary" "$env:APPDATA\npm\node_modules\@openai\codex\bin\codex.js"
```

最后新开一个 Codex CLI，输入 `/`，再打开 `/model`，确认命令说明和模型选择界面已经变成中文。

## 恢复

恢复最近一次备份：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -Restore
```

只移除 override，回到官方 `findCodexExecutable()`：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-cli-zh-binary\scripts\install-codex-cli-zh-binary.ps1" -RemoveOverride
```

## 常见问题

**这会改 Codex Desktop 吗？**

不会。它只处理 npm 安装的 Codex CLI。

**这会改我的 `config.toml`、密钥或 provider 配置吗？**

不会。脚本只改 `codex.js` wrapper，并把中文二进制放到当前用户本地目录。

**我跑了 `npm install -g @openai/codex` 后又变英文了怎么办？**

这是正常的。npm 更新会覆盖 `codex.js`，重新运行这个技能即可。

**为什么不把 300MB 的 exe 直接放进 Git？**

Git 历史不适合放大二进制。仓库只保存技能和脚本，编译产物放在 GitHub Release 资产里。

**多个 Codex 怎么办？**

脚本默认只处理当前 PATH 下第一个 `codex`。如果你要改另一个安装位置，请显式传入 `-WrapperPath`，避免误改。

## 开源与许可

本仓库里的技能和安装脚本按 Apache-2.0 许可证开源。Release 里的预编译二进制基于 OpenAI Codex CLI 源码及本地中文化改动构建；上游 npm 包声明为 Apache-2.0。这个仓库不是 OpenAI 官方发布渠道。

## Community

- [Linux Do](https://linux.do)

## 免责声明

这是社区自用的中文替换方案，不是 OpenAI 官方发行包。二进制来自对 OpenAI Codex CLI 源码的本地化构建；请只在你理解风险并信任发布者的情况下使用。安装前脚本会备份 wrapper，建议确认中文界面正常后再清理旧备份。
