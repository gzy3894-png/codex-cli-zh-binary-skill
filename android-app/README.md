# Codex for TUI Android App

这里是 Codex for TUI 的 Android 应用源码。

Codex for TUI 基于 ReTerminal 改造，目标是在 Android 手机上提供一个开箱可用的 Codex CLI 终端环境。应用内置 Alpine 入口，APK 里只保留薄启动脚本；可变化的安装、配置和更新逻辑维护在仓库的 `android-arm64-musl/` 目录。

## 这个应用做什么

- 打开应用后进入适合 Codex 运行的 Alpine 终端环境。
- 已安装 `codex` 时直接启动本地 `codex`，不拉取脚本，不刷新模型，不覆盖配置。
- 首次未安装时，用户确认安装后才拉取安装脚本和模块。
- 支持官方 Codex 登录入口，也支持第三方 Responses API。
- 第三方 API 模式在显式配置时请求 `/models`，再让用户选择默认模型。
- 脚本更新由用户手动运行 `codex-update check/apply`。

## 关键脚本

- `core/main/src/main/assets/init.sh`
- `core/main/src/main/assets/init-host.sh`
- `core/main/src/main/assets/codex-for-tui-bootstrap.sh`
- `../android-arm64-musl/lib/*.sh`
- `../android-arm64-musl/codex-update.sh`
- `../android-arm64-musl/codex-local-resume.sh`
- `../android-arm64-musl/install-reterminal-alpine.sh`

APK assets 中的 `codex-for-tui-bootstrap.sh` 必须和 `../android-arm64-musl/codex-for-tui-bootstrap.sh` 保持一致。完整安装、配置、更新逻辑只维护在 `android-arm64-musl/` 下。App 普通启动不会动态拉取它们，只有首次安装或显式更新才会联网获取。

## 更新命令

```sh
codex-update check
codex-update apply
codex-local refresh-models
```

`codex-update` 只更新脚本；`codex-local refresh-models` 只刷新第三方模型目录，并保留当前模型选择。

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
