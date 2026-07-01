# Codex for TUI

Codex for TUI 是一个面向 Android 的 Codex 终端应用。它基于 ReTerminal 改造，打开后进入 Alpine 环境，并引导用户完成 Codex 中文版的安装、依赖准备和 API 配置。

它解决的是一个很具体的问题：在手机上直接跑 Codex CLI 往往要自己处理终端、proot、Alpine、依赖、下载、环境变量、模型配置和恢复流程。Codex for TUI 把这些步骤收进一个应用里，尽量把“会劝退普通用户的一长串命令”压缩成一次可恢复的终端引导。

简单说，它是给 Android 用户准备的 Codex TUI 随身入口：装好 APK，打开终端，按提示走完安装和配置，就能在手机上进入 Codex。

## 适合谁

- 想在 Android 手机上使用 Codex CLI 的用户。
- 想用中文界面的 Codex CLI，但不想自己编译二进制的用户。
- 已经有官方 API Key，或使用兼容 Responses API 的第三方服务的用户。
- 希望配置失败后可以重新打开应用继续，而不是从头排错的用户。

## 特色

- **把复杂环境收进一个 APK**：终端、Alpine、安装脚本和恢复流程放在一起，不再要求用户先搭好一整套手机 Linux 环境。
- **面向 Codex 的启动体验**：应用不是泛用终端换壳，启动目标就是把 Codex 跑起来；未安装、未配置、配置未完成都会进入对应引导。
- **适合中文用户的 Codex CLI 路线**：自动安装 Codex 中文版 ARM64 musl 二进制，减少自己找包、传文件、改 PATH 的折腾。
- **第三方 API 配置更像正常产品流程**：输入 Base URL 和 API Key 后自动请求 `/models`，再用编号选择启用模型和默认模型。
- **输错也不容易崩盘**：本地配置支持返回、退出稍后继续；URL 粘到菜单编号处会提示纠正，非法 Base URL 不会直接拿去请求。
- **网络差时更能扛**：下载尽量使用断点续传、HTTP/1.1、重试和 SHA256 校验；依赖安装提供 Minimal / Full 两种路径。
- **手机终端友好**：纯 TUI 菜单、清晰阶段标题、选项留白，适合小屏触控、软键盘和外接键盘。
- **入口不挑大小写**：安装完成后提供 `codex`、`Codex`、`CODEX` 等大小写入口，少一点手机输入时的烦躁。

## 关键词

如果你在找 `codex`、`codex cli`、`openai codex`、`codex tui`、`codex for tui`、`codex android`、`android codex`、`codex termux`、`termux codex`、`codex alpine`、`codex proot`、`codex reterminal`、`reterminal codex`、`codex mobile`、`mobile codex`、`手机 Codex`、`手机运行 Codex`、`Android Codex CLI`、`Codex CLI Android`、`Codex 中文版`、`Codex 汉化版`、`OpenAI Codex 中文版`、`Codex CLI 中文版`、`Codex CLI 汉化项目`、`Codex CLI 中文汉化`、`codex汉化项目`、`codex 汉化项目`、`Termux Codex 中文版`、`Android Codex 汉化`、`Responses API Codex`、`第三方 API Codex`、`Alpine Codex` 或 `手机 AI 编程终端`，这个仓库提供的是面向 Android 终端的一键安装和配置路线。

## 下载

正式 APK 请到 GitHub Releases 下载：

```text
https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases
```

安装包名为 `com.gzy3894.codexfortui`。如果之前装过 debug 包，debug 包名是 `com.gzy3894.codexfortui.debug`，它和正式版不是同一个应用。

## 首次使用

1. 安装 APK 并打开应用。
2. 进入终端后按提示确认安装。
3. 选择依赖模式：
   - Minimal：下载更少，适合网络差时先跑起来。
   - Full：依赖更完整，适合长期使用。
4. 等待 Codex 中文版和依赖安装完成。
5. 选择启动提示词：
   - 默认 AGENTS.md：直接生成一份通用中文提示词。
   - 自定义 AGENTS.md：粘贴自己的提示词。
6. 选择 Codex 配置：
   - 官方登录入口：走 Codex 官方登录或 API Key 流程。
   - 第三方 Responses API：输入 Base URL 和 API Key，自动拉取模型列表。

第三方 API 的 Base URL 示例：

```text
https://api.example.com
https://api.example.com/v1
```

脚本会自动补齐 `/v1`。如果把 URL 粘到了菜单编号处，脚本会提示你先选择编号，再填写 URL。

## 日常使用

安装完成后，重新打开应用会自动进入 Codex。也可以在终端里手动运行：

```sh
codex
```

如果本地配置没有完成，重新打开应用或运行下面的命令会继续配置：

```sh
codex-local-resume
```

## 网络说明

安装过程中主要下载三类内容：

- Alpine 基础依赖。
- Codex 中文版 ARM64 压缩包。
- 可选开发依赖。

Alpine 镜像通常不一定需要代理；Codex 压缩包来自 GitHub raw，网络不稳时建议开启代理。下载会尽量使用断点续传、HTTP/1.1、重试和 SHA256 校验。

## 仓库结构

- `android-app/`：Codex for TUI Android 应用。
- `android-arm64-musl/`：Android/Alpine 安装脚本和 Codex 中文版 ARM64 说明。
- `tests/`：安装和本地配置流程的隔离 smoke test。
- `codex-cli-zh-binary/`：Windows 版 Codex CLI 中文二进制替换技能。
- `codex-cli-zh/`、`codex-android-musl-zh/`：源码汉化和构建相关技能。

## 构建与验证

仓库使用 GitHub Actions 构建 Android APK。每次构建前会先运行安装脚本 smoke test，覆盖首次安装提示、依赖选择、本地配置菜单、错误输入和 API Base URL 校验等路径。

本地只建议运行脚本测试：

```sh
sh tests/codex-for-tui-installer-smoke.sh
```

Android APK 构建建议交给 GitHub Actions，避免本机 SDK/JDK 环境差异影响结果。

## 致谢与许可

Codex for TUI 基于 ReTerminal 改造。感谢 ReTerminal 官方项目和作者 Rohit Kushvaha 提供 Android 终端、proot 和 Alpine 能力基础：

```text
https://github.com/RohitKushvaha01/ReTerminal
```

感谢 OpenAI Codex CLI 上游项目。Codex for TUI 只是围绕 Android 终端环境、中文构建和安装配置流程做整理与集成，不是 OpenAI 官方发布渠道。

本仓库脚本和改动按 Apache-2.0 许可证开源。Codex 中文版二进制基于 OpenAI Codex CLI 源码及本地中文化改动构建。

## 社区

本项目认可并感谢 Linux Do 社区。Codex for TUI 的使用反馈、问题排查和改进方向可以在中文开发者社区中继续交流。

```text
https://linux.do
```

## 免责声明

这是社区维护的 Android Codex 终端方案。安装前请确认你信任本仓库、Release 资产和对应校验信息。API Key 会写入应用内 Alpine 环境的 Codex 配置目录，请妥善保管设备和应用数据。
