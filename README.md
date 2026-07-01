# Codex for TUI

[![Release](https://img.shields.io/badge/release-v1.0.2-blue)](https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/tag/codex-for-tui-v1.0.2)
[![Codex](https://img.shields.io/badge/Codex%20CLI-0.142.4-111827)](./android-arm64-musl/README.md)
[![Target](https://img.shields.io/badge/target-android%20arm64%20musl-0f766e)](./android-arm64-musl/README.md)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](./LICENSE)

Codex for TUI 是一个面向 Android 手机的 Codex CLI 终端应用。它基于 ReTerminal 改造，内置 Alpine/proot 终端环境和 Codex 中文版 ARM64 musl 安装流程，让用户不必先手动折腾 Termux、rootfs、依赖、PATH、API 配置和恢复脚本。

一句话：安装 APK，打开终端，按提示完成依赖和 API 配置，就可以在手机上进入 Codex TUI。

## 项目定位

这个仓库解决的是 Android 上运行 Codex CLI 的一整套落地问题：

- 终端入口：提供可直接打开的 Android 终端应用，而不是只给一段命令。
- 运行环境：使用 Alpine/proot 路线承载 `aarch64-unknown-linux-musl` 构建。
- 安装流程：自动准备依赖、下载 Codex 中文版二进制、写入 PATH 和大小写命令入口。
- 配置流程：支持官方 Codex 初始化，也支持兼容 OpenAI Responses API 的第三方服务。
- 恢复流程：配置中断、网络失败或输入错误后，重新打开应用可以继续，不需要从零排查。

它不是 OpenAI 官方发布渠道，也不是一个泛用 Linux 发行版 App；它的目标很明确：让 Android 用户更稳地进入 Codex TUI。

## 当前版本

| 项目 | 当前值 |
| --- | --- |
| Android App | `1.0.2` |
| 包名 | `com.gzy3894.codexfortui` |
| Debug 包名 | `com.gzy3894.codexfortui.debug` |
| Codex CLI | `0.142.4` 中文版 |
| 二进制目标 | `aarch64-unknown-linux-musl` |
| 推荐设备 | Android 8.0+、ARM64 |
| 默认分支 | `android-arm64-musl-installer` |

已知边界：

- 这是社区构建，不是 OpenAI 官方 APK。
- 当前核心二进制面向 Android/Alpine ARM64 musl 环境。
- musl 构建中的 Code Mode 已禁用，主要面向 Codex TUI 日常对话、代码协作和终端工作流。
- API Key 会写入应用内 Alpine 环境的 Codex 配置目录，请只在可信设备上使用。

## 下载

正式版 APK 请从 Releases 下载：

```text
https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases
```

下载时选择 APK 文件，不要下载 GitHub 自动生成的 `Source code` 压缩包。若你之前安装过 Debug 包，它和正式版包名不同，可以共存；正式版包名是 `com.gzy3894.codexfortui`。

## 首次使用

1. 安装 APK 并打开 Codex for TUI。
2. 进入终端后，App 会先拉取最新安装脚本，再按提示确认安装 Codex 环境。
3. 选择依赖模式：
   - `Minimal`：下载更少，适合网络差时先跑起来。
   - `Full`：依赖更完整，包含 Python、Node/npm、编译工具链等，适合长期使用。
4. 等待 Alpine 依赖和 Codex 中文版二进制安装完成。
5. 选择启动提示词：
   - 使用默认中文 `AGENTS.md`。
   - 或粘贴自己的 `AGENTS.md`。
6. 选择 Codex 配置方式：
   - 官方入口：保留官方 Codex 登录/API Key 初始化流程。
   - 第三方 Responses API：输入 Base URL 和 API Key，脚本会请求 `/models`，再让你选择常用模型和默认模型。

第三方 API Base URL 示例：

```text
https://api.example.com
https://api.example.com/v1
```

脚本会自动补齐 `/v1`。如果把 URL 粘到了菜单编号处，安装器会提示你先选择编号，再填写 URL。

## 日常使用

安装完成后，重新打开 App 会自动进入 Codex。若配置未完成，App 会先刷新最新恢复脚本再继续。也可以在终端里手动运行：

```sh
codex
```

如果配置没走完、网络中断或你主动退出过配置流程，重新打开 App 会继续。也可以手动恢复：

```sh
codex-local-resume
```

安装器还会创建多种大小写入口，例如：

```sh
codex
Codex
CODEX
```

这对手机软键盘输入很有用。

## 为什么推荐 APK 路线

Android 上手动安装 Codex CLI 通常会踩到这些问题：

- 终端 App、proot、Alpine rootfs、依赖和 PATH 都要自己配。
- GitHub、Alpine 镜像、代理和移动网络组合后，下载经常不稳定。
- 第三方 API 不只是填一个 Key，还要处理 Base URL、`/models`、模型列表、鉴权和默认模型。
- 配置失败后很容易不知道该重新执行哪一步。

Codex for TUI 把这些步骤变成了一个可恢复的终端引导：能下载就继续，失败就提示，退出后还可以接着来。

## 高级安装脚本

如果你已经在 ReTerminal Alpine、Termux + Alpine proot 或其他兼容环境里，也可以只使用本仓库的安装脚本。

ReTerminal Alpine 推荐命令：

```sh
wget -O - https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh | sh
```

已有 `curl` 时：

```sh
curl -fsSL https://raw.githubusercontent.com/gzy3894-png/codex-cli-zh-binary-skill/android-arm64-musl-installer/android-arm64-musl/install-reterminal-alpine.sh | sh
```

更多 Termux、Alpine proot、非交互配置和环境变量说明见：

```text
android-arm64-musl/README.md
```

## 网络与校验

安装过程主要下载三类内容：

- Alpine 基础依赖。
- Codex 中文版 ARM64 musl 压缩包。
- 可选开发依赖。

Alpine 依赖通常可以走国内镜像；Codex 压缩包来自 GitHub Release，网络不稳时建议开启代理。下载器会尽量使用断点续传、HTTP/1.1、重试和 SHA256 校验。

当前 Codex 二进制校验值：

```text
7BEC4F162DDE06C8B14F2D50309E4999D8239C5AD9E7A138509B0E758007CB29  codex-0.142.4-zh-aarch64-unknown-linux-musl.tar.gz
40626C9FF0A63A04DD6BC5D2120CD418E07C5306202BD955F34EFE761B05E423  codex-0.142.4-zh-aarch64-unknown-linux-musl
```

校验文件位于：

```text
android-arm64-musl/SHA256SUMS
```

## 常见问题

**打开 App 后没有进入 Codex，而是回到了 shell？**

通常是安装或配置流程中断了。先运行：

```sh
codex-local-resume
```

如果提示缺依赖，按菜单重新安装依赖即可。

**下载 Codex 压缩包很慢或失败？**

Codex 压缩包在 GitHub Release。建议开启代理/VPN 后重新打开 App，安装器会尽量继续已有下载。

**第三方 API 配置失败？**

确认服务兼容 OpenAI Responses API，并测试 `/models`：

```sh
curl -v --http1.1 https://api.example.com/v1/models
```

如果返回 `401`，通常说明网络通了，但缺少 Authorization；如果连不上，多半是 Base URL、代理或服务端兼容性问题。

**Codex 结束时出现 hook 相关错误？**

安装器默认写入：

```toml
[features]
hooks = false
```

如果你迁移过旧配置，可以检查 `~/.codex/config.toml` 里是否仍有旧 hook 配置。

**能不能直接用原生 Termux？**

仓库保留了原生 Termux 安装脚本，但更推荐 Alpine/proot 路线。部分设备和代理环境下，原生 Termux 更容易遇到流式输出断连、SSL EOF、依赖源不稳定等问题。

## 仓库结构

```text
.
├── android-app/          # Codex for TUI Android 应用源码
├── android-arm64-musl/   # Android/Alpine 安装脚本、校验文件和二进制说明
├── tests/                # 安装器和配置流程 smoke test
└── .github/workflows/    # GitHub Actions APK 构建流程
```

维护脚本时要注意：`android-arm64-musl/` 下的脚本是主要维护源，APK assets 里也有副本，改动后需要保持同步。

## 构建与验证

本仓库使用 GitHub Actions 构建 release APK。构建前会先运行安装器 smoke test，覆盖首次安装提示、依赖选择、本地配置菜单、错误输入、API Base URL 校验等路径。

本地建议先跑脚本级测试：

```sh
sh tests/codex-for-tui-installer-smoke.sh
```

APK 构建建议交给 GitHub Actions，避免本地 JDK、Android SDK、NDK 和 Gradle 环境差异影响结果。

## 搜索关键词

如果你在找这些方向，这个项目就是对应路线：

```text
Codex Android, Codex CLI Android, Codex TUI, Codex for TUI,
Termux Codex, ReTerminal Codex, Alpine Codex, proot Codex,
Codex 中文版, Codex CLI 中文版, Codex 汉化版, 手机 AI 编程终端
```

## 社区

本开源项目已链接并认可 [LINUX DO 社区](https://linux.do)。

Codex for TUI 的使用反馈、安装排错和改进建议可以在 GitHub Discussions 中交流：

```text
https://github.com/gzy3894-png/codex-cli-zh-binary-skill/discussions
```

## 致谢

Codex for TUI 基于 ReTerminal 改造。感谢 ReTerminal 官方项目和作者 Rohit Kushvaha 提供 Android 终端、proot 和 Alpine 能力基础：

```text
https://github.com/RohitKushvaha01/ReTerminal
```

感谢 OpenAI Codex CLI 上游项目。本仓库只是围绕 Android 终端环境、中文构建和安装配置流程做整理与集成。

也感谢 Linux Do 社区对移动端 Codex 使用、排错和改进方向的反馈。

## 许可与免责声明

本仓库脚本和改动按 Apache-2.0 许可证开源。Codex 中文版二进制基于 OpenAI Codex CLI 源码及本地中文化改动构建。

安装前请确认你信任本仓库、Release 资产和对应校验信息。API Key 会写入应用内 Alpine 环境的 Codex 配置目录，请妥善保管设备和应用数据。
