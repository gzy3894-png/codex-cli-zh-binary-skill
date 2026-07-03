# Codex for TUI Android App

这里是 Codex for TUI 的 Android 应用源码。

Codex for TUI 基于 ReTerminal 改造，目标是在 Android 手机上提供一个开箱可用的 Codex CLI 终端环境。应用内置 Alpine 入口，APK 里只保留薄启动脚本；可变化的安装、配置和更新逻辑维护在仓库的 `android-arm64-musl/` 目录。

## 这个应用做什么

- 打开应用后进入适合 Codex 运行的 Alpine 终端环境。
- 已安装 `codex` 时直接启动本地 `codex`，不拉取脚本，不刷新模型，不覆盖配置。
- 首次未安装时，用户确认安装后才拉取安装脚本和模块。
- 支持官方 Codex 登录入口，也支持第三方 Responses API。
- 第三方 API 模式在显式配置时请求 `/models`，再让用户选择默认模型。
- 脚本更新由用户手动运行 `codex 更新`。

## 关键脚本

- `core/main/src/main/assets/init.sh`
- `core/main/src/main/assets/init-host.sh`
- `core/main/src/main/assets/codex-for-tui-bootstrap.sh`
- `core/main/src/main/assets/codex-preview`
- `core/main/src/main/assets/codex-push-image`
- `core/main/src/main/assets/codex-push-media`
- `../android-arm64-musl/lib/*.sh`
- `../android-arm64-musl/codex-update.sh`
- `../android-arm64-musl/codex-local-resume.sh`
- `../android-arm64-musl/install-reterminal-alpine.sh`

APK assets 中的 `codex-for-tui-bootstrap.sh` 必须和 `../android-arm64-musl/codex-for-tui-bootstrap.sh` 保持一致。完整安装、配置、更新逻辑只维护在 `android-arm64-musl/` 下。App 普通启动不会动态拉取它们，只有首次安装或显式更新才会联网获取。

## 更新命令

```sh
codex 更新
codex 配置模式
codex-update check
codex-update apply
codex-local refresh-models
```

`codex 更新` 只增量更新脚本，不重装依赖、不替换 Codex 二进制；`codex 配置模式` 重新进入第三方 API 配置引导。安装器不管理 `AGENTS.md`，需要项目规则时请在 Codex 内运行 `/init`。

## 文件面板

测试包内置原生文件面板。终端内运行：

```sh
codex-preview /path/to/image.png
codex-preview /path/to/notes.md
codex-push-image /path/to/image.png
codex-push-media /path/to/video.mp4
codex-preview path 1783070528.24966
codex-preview close
```

命令会把图片、视频或文本复制到 App 私有目录，并通知前台终端界面在内嵌文件容器中展示。
多次推送会累积为缩略图文件面板；图片点击后进入全屏缩放预览，多张图片可左右滑动查看，视频使用系统级 Media3 控件播放，文本文件只展示摘要，不把全文刷到终端。文件面板内也可以通过系统文件管理器选择文本、图片或视频。发送文件时可以附加一句话，终端只显示短文件编号；AI 需要真实路径时可运行 `codex-preview path <编号>` 解析。

## 浏览器

终端内运行：

```sh
codex-browser open https://example.com
codex-browser auth https://chatgpt.com
codex-browser external https://example.com/login
```

`open` 使用 App 内嵌 WebView，适合展示页面、读取 DOM、点击、输入和截图。`auth` / `external` 使用 Chrome Custom Tabs 或系统浏览器，适合登录、授权、验证码和风控场景；该模式不向 App 暴露用户浏览器 Cookie。
浏览器托盘支持多标签，顶部标签条可以切换或关闭标签；文件和浏览器托盘都采用更紧凑的入口按钮和更轻的半透明容器，减少对终端内容的遮挡。

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
