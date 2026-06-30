# Codex CLI 中文二进制替换技能

这是一个 Codex CLI 汉化项目 / 中文汉化 Skill，面向 Windows 上通过 npm 安装的 OpenAI Codex CLI。它用预编译的中文 `codex.exe` 接管当前 npm wrapper，适合想把本机 `codex` 命令切到 Codex 中文版、但不想重新编译源码的场景。

如果你在找 `codex汉化项目`、`codex 汉化项目`、`Codex CLI 汉化项目`、`Codex CLI 中文汉化`、`Codex 中文版`、`Codex 汉化版`、`OpenAI Codex 中文版`、`codex.exe 中文版`、`codex 源码汉化`、`Codex 编译汉化`、`Termux Codex 中文版`、`Android Codex 汉化` 或 Windows 下的一键中文化方案，这个仓库提供的是“不编译源码，只替换当前 npm wrapper 指向的二进制”的路径。

当前 `main` 分支发布的是二进制替换技能；`compile-skill` 分支发布源码编译技能，面向需要自己从 OpenAI Codex 官方源码打补丁并编译的用户。

## Android ARM64 一键安装分支

`android-arm64-musl-installer` 分支发布 Android/Termux ARM64 一键安装包，包含 Codex CLI `0.142.4` 中文版 `aarch64-unknown-linux-musl` 压缩包和自动安装脚本。

刚装好的 Termux / Termux 裸环境用这一条。它会先安装下载器和证书，然后脚本继续安装 Codex 运行依赖和常见工作环境依赖：

```sh
pkg update -y && pkg install -y ca-certificates curl && curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

如果环境已经有 `curl`，可以直接执行：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

如果只有 `wget`，可以执行：

```sh
wget -O- https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | sh
```

默认会安装这些 Termux 工作环境依赖：

- Codex 下载/运行：`ca-certificates`、`curl`、`wget`、`tar`、`gzip`、`unzip`、`xz-utils`
- 代码工作流：`git`、`openssh`、`ripgrep`、`fd`、`jq`
- 常用语言环境：`python`、`python-pip`、`nodejs`、`npm`
- Shell/文本/补丁工具：`bash`、`coreutils`、`findutils`、`sed`、`grep`、`gawk`、`diffutils`、`patch`
- 常见本地编译依赖：`make`、`clang`、`binutils`、`lld`、`pkg-config`、`cmake`、`ninja`、`openssl`、`libffi`、`perl`、`procps`、`termux-tools`

如果只想安装轻量运行依赖：

```sh
pkg update -y && pkg install -y ca-certificates curl && curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install.sh | CODEX_ZH_DEPS_PROFILE=minimal sh
```

没有 `pkg`、`curl`、`wget` 的纯 Android shell 不能远程一键安装；需要先手动提供下载器或本地复制安装文件。脚本会自动安装终端依赖、下载汉化版 ARM64 musl 二进制、校验 SHA256，并把 `codex` 命令指向 `codex-zh`。

## 编译技能分支

源码编译技能在 `compile-skill` 分支：

```powershell
git clone -b compile-skill https://github.com/gzy3894-png/codex-cli-zh-binary-skill.git
Copy-Item -Recurse -Force .\codex-cli-zh-binary-skill\codex-cli-zh "$env:USERPROFILE\.codex\skills\codex-cli-zh"
Copy-Item -Recurse -Force .\codex-cli-zh-binary-skill\codex-android-musl-zh "$env:USERPROFILE\.codex\skills\codex-android-musl-zh"
```

它包含：

- `codex-cli-zh`：源码级汉化、Windows x64 构建、macOS 本机构建、覆盖扫描和 Windows npm wrapper 安装。
- `codex-android-musl-zh`：从 Windows 交叉编译 `aarch64-unknown-linux-musl` 中文 Codex CLI。
- `codex-cli-zh-slash-patch` / `codex-cli-zh-deep-patch`：拆分版 slash 命令和深层 TUI 文案补丁技能。

已验证支持：

- Windows x64：Codex CLI `0.142.2`、`0.142.4`
- Windows x64 当前发布基线：Codex CLI `0.142.4`
- ARM64 musl：Codex CLI `0.142.4`，目标 `aarch64-unknown-linux-musl`

macOS 支持：

- `compile-skill` 分支包含 `codex-cli-zh/scripts/build-codex-cli-zh-macos.sh`。
- 支持 macOS 本机 patch + Cargo build，可传 `--repo-ref rust-v0.142.4` 或 `--target aarch64-apple-darwin`。
- 当前维护主机是 Windows，无法在本次发布中宣称 macOS 产物已真机运行验证；后续有 macOS 机器后应补充实际哈希和 `codex --version` 验证记录。

它的改动范围刻意保持很小：不改用户配置、不碰 CC Switch、不处理 Codex Desktop，只定位当前终端实际会执行的 npm wrapper，并让新开的 Codex CLI 启动中文二进制。

当前预编译二进制基于 Codex CLI `0.142.4`。本地验证过的 Windows x64 产物信息：

- 版本：`codex-cli 0.142.4`
- SHA256：`0DD8649E0C19FA57590D2F7B674FFDFE278744E2DCCC4036C28DB168B2E073A5`
- 汉化覆盖：授权/审批、登录/API key、信任目录、MCP、`/` 命令弹窗和次级页面等高频 TUI 文案。

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
codex-cli 0.142.4
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

本项目认可并感谢 [Linux Do](https://linux.do) 社区。相关交流、反馈和使用经验可以在 Linux Do 社区中展开。

## 免责声明

这是社区自用的中文替换方案，不是 OpenAI 官方发行包。二进制来自对 OpenAI Codex CLI 源码的本地化构建；请只在你理解风险并信任发布者的情况下使用。安装前脚本会备份 wrapper，建议确认中文界面正常后再清理旧备份。
