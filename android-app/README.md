# Codex for TUI Android App

这里是 Codex for TUI 的 Android 应用源码。

Codex for TUI 基于 ReTerminal 改造，目标是在 Android 手机上提供一个开箱可用的 Codex CLI 终端环境。应用内置 Alpine 入口，并通过 assets 中的脚本完成 Codex 中文版安装、依赖准备、本地配置恢复和启动。

## 这个应用做什么

- 打开应用后进入适合 Codex 运行的 Alpine 终端环境。
- 首次启动时引导用户安装依赖和 Codex 中文版 ARM64 musl 二进制。
- 支持官方 Codex 登录入口，也支持第三方 Responses API。
- 第三方 API 模式会自动请求 `/models`，再让用户选择启用模型和默认模型。
- 本地配置未完成时可以重新打开应用继续，不需要从头安装。

## 关键脚本

- `core/main/src/main/assets/init.sh`
- `core/main/src/main/assets/codex-for-tui-bootstrap.sh`
- `core/main/src/main/assets/install-reterminal-alpine.sh`
- `core/main/src/main/assets/codex-local-resume.sh`

这些脚本的源文件主要维护在仓库根目录的 `android-arm64-musl/` 下。修改后要保持 assets 副本同步。

## 构建

推荐使用仓库的 GitHub Actions 构建 release APK。构建前会先运行安装器 smoke test。

本地只建议做脚本级验证：

```sh
sh tests/codex-for-tui-installer-smoke.sh
```

## 致谢

本应用基于 ReTerminal 改造。感谢 ReTerminal 官方项目和作者 Rohit Kushvaha 提供 Android 终端、proot 和 Alpine 能力基础：

```text
https://github.com/RohitKushvaha01/ReTerminal
```

感谢 OpenAI Codex CLI 上游项目。Codex for TUI 只是围绕 Android 终端环境、中文构建和安装配置流程做整理与集成，不是 OpenAI 官方发布渠道。

## 社区

本项目认可并感谢 Linux Do 社区：

```text
https://linux.do
```
