# Codex for TUI

[![Release](https://img.shields.io/badge/release-v2.2.6-blue)](https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/tag/codex-for-tui-v2.2.6)
[![Codex](https://img.shields.io/badge/Codex%20CLI-0.142.4-111827)](./android-arm64-musl/README.md)
[![Target](https://img.shields.io/badge/target-android%20arm64%20musl-0f766e)](./android-arm64-musl/README.md)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](./LICENSE)

Codex for TUI 是一个面向 Android 手机的 Codex CLI 终端应用。它基于 ReTerminal 改造，内置 Alpine/proot 终端环境、Codex 中文版 ARM64 musl 安装流程、文件托盘和协作浏览器，让用户不必先手动折腾 Termux、rootfs、依赖、PATH、API 配置、本地维护命令和移动端预览工具。

一句话：安装 APK，打开终端，按提示完成依赖和 API 配置，就可以在手机上进入 Codex TUI。

## 重要：2.2.6 更新

2.2.6 是 bridge 并发可靠性和安全加固版：浏览器、文件托盘、会话折叠和 Agent 面板请求改为更稳的队列/幂等处理，避免同一请求被 legacy request 与 queue 双执行，也避免快速连续请求覆盖丢失；协作浏览器加强导航超时和旧页面回调隔离，外部链接/下载统一进入可确认的用户协作状态；同时收窄敏感数据备份、FileProvider、Release 签名和 GitHub Release 发布门禁。

2.2.5 的 RTK hook 安全热修继续保留：`codex-rtk hook` 会把改写结果中的 `rtk ...` 转为 App 内置 RTK 的绝对路径，避免少数登录 shell 的 `PATH` 没带 `$PREFIX/local/bin` 时出现 `rtk: not found`；同时遇到复杂 `find ... -exec ...` 等 RTK 不支持的命令会直接保留原命令，避免误改写失败。2.2.3 的终端输出合帧、Compose 状态去重、bridge 低频兜底轮询，以及打开 Custom Tabs/外部浏览器后 bridge 继续消费请求的修复继续保留。新增 `$PREFIX/local/perf/terminal.status` 作为轻量排障状态文件，便于 Agent 判断合帧和 bridge 工作状态。

2.2.1 的浏览器协作能力继续保留：`auth-open` 默认只打开 App 内安全登录任务卡，不再自动跳出到 Custom Tabs；用户点击“打开/重开”或 Agent 显式调用 `auth-reopen` / `auth-open --open-now` 时才打开系统浏览器。2.2.0 新增的调用式 Custom Tabs 安全登录任务卡，`auth-open/auth-wait/auth-status/auth-done/auth-cancel/auth-reopen` 会把用户完成、取消、折叠、重开等动作结构化回传给 Agent；官方 Codex 登录可走 `codex 官方登录` / 启动前设备码向导，默认使用 `codex login --device-auth`，在安全登录任务卡中展示链接/验证码，用户点击“打开/重开”进入 Custom Tabs 完成授权后再用 `codex login status` 验证。

内置 WebView 继续作为 Agent Browser，保留后台打开、DOM 读取、点击、输入、JS、截图、多标签、Cookie/WebStorage 持久化和 userscript；遇到验证码/风控/外部 scheme 时会进入明确的用户协作状态，而不是让 Agent 猜。

已经安装 2.0.x/2.1.x/2.2.x 的用户需要从 Releases 下载并覆盖安装 2.2.6 APK。覆盖安装后重新打开终端，新会话会自动同步 `codex-panel`、`codex-preview`、`codex-browser`、`codex-session`、`codex-rtk`、`codex-context` 等 APK 内置桥接命令。

注意：普通启动按设计不会自动联网更新 `~/.local/share/codex-zh/scripts` 下的安装/配置脚本。已安装用户覆盖 APK 后，为确保 `codex 配置模式` 也切到最新配置管理器，请手动执行一次：

```sh
codex 更新
codex-local repair-launcher
```

然后进入配置菜单：

```sh
codex 配置模式
```

如果菜单里能看到 `1. 新建配置 / 2. 选择配置 / 3. 编辑当前配置 / 4. 查看配置 / 5. 删除配置`，说明脚本已经更新到配置管理器版本。新建或编辑第三方 API 后会主动询问是否保存为配置档；切换配置或退出配置模式前，如果当前配置有未保存修改，会先提示保存，避免配置档为空或丢失。

新安装、尚未完成首次安装的用户，首次安装时会拉取当前分支的最新脚本；普通启动仍然不会隐藏联网更新、不会刷新模型、不会覆盖用户配置。已安装用户运行 `codex 更新` 再运行 `codex-local repair-launcher` 后，新启动器会带上最新桥接命令、快捷授权菜单和配置管理器。

## 2.0 新功能

- 2.2.6 修复：bridge 请求队列和 request_id 幂等，避免浏览器请求双执行、文件托盘/session fold/agent panel 快速连续请求丢失。
- 2.2.6 修复：协作浏览器导航 token、状态落盘、外部链接/下载确认和敏感字段脱敏，减少后台浏览和用户协作状态错乱。
- 2.2.6 加固：DocumentsProvider 路径边界、备份排除、FileProvider 分享范围、Release 签名和 GitHub Release 资产发布门禁。
- 2.2.6 加固：2.x 既有正式签名迁移到 `app/codex-for-tui-2x-release.keystore`，release 构建不再借用 debug signingConfig。
- 2.2.5 修复：RTK hook 使用 App 内置 RTK 绝对路径，并跳过复杂 `find` 改写，避免 `rtk: not found` 和 `rtk find` 不支持参数导致的命令失败。
- 2.2.4 修复：RTK hook 使用 App 内置 RTK 绝对路径，避免登录 shell `PATH` 缺失时出现 `rtk: not found`。
- 2.2.3 修复：打开 Custom Tabs/外部浏览器后，文件托盘、浏览器和会话折叠 bridge 继续消费 Agent 请求，避免回到终端后状态卡在旧任务。
- 2.2.2 优化：终端输出按屏幕帧合并刷新，Compose 状态去重，bridge 事件触发加低频兜底轮询，减少长输出时卡顿。
- 2.2.1 修复：`auth-open` 默认只弹 App 内任务卡，不自动跳 Custom Tabs；需要立刻打开时用 `--open-now`，旧 `auth/external/custom-tab` 仍保持立即打开兼容。
- 2.2.0 新增：调用式 Custom Tabs Auth Browser，`auth-open/auth-wait/auth-status/auth-done/auth-cancel/auth-reopen` 支持安全登录/验证任务卡和用户动作回传。
- 2.2.0 新增：官方 Codex 设备码登录向导，`codex 官方登录` 会调用 `codex login --device-auth`，解析登录链接/验证码并创建安全登录任务卡。
- 2.2.0 增强：WebView Agent Browser 增加验证码/风控检测、外部 scheme 打开确认、Auth/外部打开状态字段和更明确的折叠/完成/取消事件。
- 2.1.3 修复：协作浏览器 userscript 注入改为延迟重试、回调解析和日志记录；注入失败会反馈给 `codex-browser`，避免静默失败。
- 2.1.2 新增/修复：`codex 配置模式` 改为配置管理器，支持配置增删改查；新建/编辑后主动询问保存，切换/退出前保护未保存配置。
- 2.1.1 修复：`codex-browser` 请求队列发布竞态、桥接轮询异常退出、userscript 注入回调抢跑。
- 2.1.0 新增：`codex-browser` 请求队列、多标签列表、历史、Cookie 状态/验证、截图推送文件托盘、userscript 本地注入。
- 2.1.0 新增：内置终端预设背景图，默认透明度为 1；用户自定义背景优先。
- 2.0.8 修复：RTK/context 改为启动前终端快捷授权，授权后写入系统级 `requirements.toml` 托管 hooks，不再要求普通用户进入 `/hooks` 手动信任。
- 2.0.8 新增：`codex-context status|events|hook|enable|disable|verify`，记录自动/手动 compact 和 session start 事件，便于后续 Agent 接续。
- 2.0.8 修复：会话托盘运行中耗时自动刷新，不再只在 Agent 主动传参时变化。
- 2.0.7 新增：内置 RTK `v0.43.0`，提供 `codex-rtk status|enable|disable|verify|hook`；RTK 用来压缩未来 shell 命令输出，不会删除已经进入 Codex 的历史上下文。
- 2.0.7 新增：会话时间线支持整体折叠，`codex-session timeline collapse|expand|toggle` 只改变托盘显示，不清空 run/item 记录。
- 2.0.6 新增：会话折叠 v1，`codex-session` 支持 `start/add/done/fail/expand/collapse/remove/clear/status/events/wait/result`，长文本和工具输出进入结构化折叠时间线，不直接刷满终端。
- 2.0.5 补丁：修复运行时调试发现的协议字段一致性问题，后台加入文件时 `status files` 会带上 `item_id/name/stamp`，删除文件后的 `active_item` 会反映真实当前项，浏览器 `status/result` 会带上 `active_item/tab_id/tabs_count`。
- 2.0.4 补丁：新增统一 `codex-panel` Agent 面板入口，文件托盘和协作浏览器的展示、折叠、切换、完成、取消、清空、关闭、选择、删除都能通过同一套命令和结构化事件读写。
- 双向事件：用户展开/折叠托盘、打开/关闭预览、长按分享、选择/删除/发送文件、发送长文本、浏览器标签选择/关闭、等待用户协作和用户完成都会写入 `status/events/result`。
- 文件托盘：终端可以推送图片、视频和文本到顶部托盘，用户也可以从系统文件管理器添加文件，第一格常驻文本框可发送长文本。
- 隐私友好的文件引用：发送到终端时只展示短编号和 `codex-preview path <编号>`，不再把应用私有目录完整刷到屏幕里。
- 协作浏览器：内置 WebView 默认后台运行，只有 `present` / `user-wait`（兼容 `wait-user`）或用户点顶栏时才展示；支持 Agent 读取页面、点击、输入、执行 JS、截图、文件上传、用户接管和多标签切换。
- 登录/验证场景：需要真实浏览器能力时可从任务卡跳转 Custom Tabs 或系统浏览器，由用户完成登录、授权或验证后再回到 TUI。
- 移动端体验：文件和浏览器入口更紧凑，托盘容器更轻，减少遮挡终端内容。

## 项目定位

这个仓库解决的是 Android 上运行 Codex CLI 的一整套落地问题：

- 终端入口：提供可直接打开的 Android 终端应用，而不是只给一段命令。
- 运行环境：使用 Alpine/proot 路线承载 `aarch64-unknown-linux-musl` 构建。
- 安装流程：自动准备依赖、下载 Codex 中文版二进制、写入 PATH 和大小写命令入口。
- 配置流程：支持官方 Codex 初始化，也支持兼容 OpenAI Responses API 的第三方服务。
- 文件协作：支持图片、视频、文本预览、用户选文件、长按分享和带说明发送。
- 浏览器协作：支持内置 WebView、Custom Tabs/系统浏览器接管、多标签和页面自动化桥接。
- 本地维护：普通启动不改配置；脚本更新和模型目录刷新都由用户显式命令触发。

它不是 OpenAI 官方发布渠道，也不是一个泛用 Linux 发行版 App；它的目标很明确：让 Android 用户更稳地进入 Codex TUI。

## 当前版本

| 项目 | 当前值 |
| --- | --- |
| Android App | `2.2.6` |
| 包名 | `com.gzy3894.codexfortui` |
| Debug/Test 包名 | `com.gzy3894.codexfortui.test` |
| Codex CLI | `0.142.4` 中文版 |
| 二进制目标 | `aarch64-unknown-linux-musl` |
| 推荐设备 | Android 8.0+、ARM64 |
| 默认分支 | `android-arm64-musl-installer` |
| 2.x 正式 APK 签名证书 SHA-256 | `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc` |

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

Codex for TUI 2.x 正式版沿用同一个 APK 签名证书，以保证用户可以正常覆盖升级。GitHub Actions 的 release 构建会校验签名证书 SHA-256，必须等于：

```text
a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc
```

如果未来需要切换签名，必须作为不兼容升级单独公告，旧版用户不能直接覆盖安装。

## 首次使用

1. 安装 APK 并打开 Codex for TUI。
2. 首次未安装时，App 会先显示安装确认；确认后才下载安装脚本和模块。
3. 等待 Alpine 依赖和 Codex 中文版二进制安装完成。
4. 选择 Codex 配置方式：
   - 官方入口：保留官方 Codex 登录/API Key 初始化流程。
   - 第三方 Responses API：输入 Base URL 和 API Key，脚本会请求 `/models`，再让你选择默认模型。

第三方 API Base URL 示例：

```text
https://api.example.com
https://api.example.com/v1
```

脚本会自动补齐 `/v1`。如果把 URL 粘到了菜单编号处，安装器会提示你先选择编号，再填写 URL。

## 日常使用

安装完成后，重新打开 App 会直接进入本地 `codex`，不会自动联网更新脚本，不会自动刷新 `/models`，也不会覆盖 `~/.codex/config.toml`。也可以在终端里手动运行：

```sh
codex
```

脚本更新需要用户手动执行。推荐直接输入：

```sh
codex 更新
```

`codex 更新` 只增量更新安装/配置脚本，不重装 Alpine 依赖，不替换 Codex 二进制，不覆盖通用配置。底层等价维护入口仍然保留：

```sh
codex-update check
codex-update apply
```

需要新建、编辑、切换或保存第三方 API 配置时，输入：

```sh
codex 配置模式
```

`codex 配置模式` 会打开配置管理器，围绕配置的增、删、改、查和切换工作：新建配置、选择配置、编辑当前配置、查看配置、删除配置、保存当前配置、刷新模型目录和修复全权限授权。第三方配置会写入 `config.toml`、`auth.json` 和 `model_catalog_json`；新建或编辑完成后会主动询问是否保存为配置档，切换或退出前会提示保存未保存修改。通用配置如自动压缩、fast mode、goals、statusline 会保留；全权限模式会同时写入 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`，避免只显示 never 但实际仍受沙箱限制。

第三方模型目录刷新也可以手动执行；它只更新 `model_catalog_json` 指向的模型目录文件，保留当前 `model` 和 `model_reasoning_effort`：

```sh
codex-local refresh-models
```

本地诊断和启动器修复：

```sh
codex-local doctor
codex-local repair-launcher
```

文件托盘可以由终端命令唤起，用来把本地图片、视频或文本放到顶部容器里预览。默认会展示托盘；需要只放入后台托盘时使用 `--background`：

```sh
codex-preview /path/to/image.png
codex-preview --background /path/to/video.mp4
printf '很长的文本\n' | codex-preview text --stdin --name notes.txt
```

用户也可以在托盘里点“添加”，用 Android 系统文件管理器选择文件。托盘第一格是常驻文本框，发送后会保存为文本引用并清空输入框；文件卡片发送时可以附加一句说明。终端提示只会展示短文件编号；需要在 shell 中解析真实路径时使用：

```sh
codex-preview path <编号>
```

托盘和浏览器都会写入统一事件流，Agent 可以读取用户折叠、完成、取消、删除、清空、发送等状态：

```sh
codex-preview status
codex-preview events
```

统一 Agent 面板入口适合自动化脚本使用，`files` 指文件/文本托盘，`browser` 指协作浏览器：

```sh
codex-panel status
codex-panel events
codex-panel present files 查看文件
codex-panel collapse files 已读取
codex-panel clear files 清理托盘
codex-panel present browser 展示页面
codex-panel collapse browser 后台继续
codex-panel done browser 用户已完成
codex-panel result browser
```

事件和结果会包含 `visible`、`collapsed`、`request_id`、`item_id`、`active_item`、`reason`，并附带文件类型、路径、浏览器 URL、标题、标签数、是否等待用户等参数。

协作浏览器由应用内桥接驱动。`open` 默认后台加载，不会立刻弹出；需要展示给用户时再调用 `present`，需要用户协作时用 `user-wait`（也兼容 `wait-user`）：

```sh
codex-browser --no-wait open 'https://www.baidu.com/s?wd=codex'
codex-browser status
codex-browser list-tabs
codex-browser cookies verify 'https://www.baidu.com'
codex-browser screenshot --push
codex-browser present 搜索结果已就绪
codex-browser user-wait 请完成登录或验证
codex-browser status
codex-browser events
codex-browser auth-open --reason 'Codex 官方登录' --code 'ABCD-EFGH' 'https://chatgpt.com/activate'
# 如确实需要立即跳系统浏览器：codex-browser auth-open --open-now --reason '登录' 'https://example.com/login'
codex-browser auth-wait '<request_id>'
```

Agent 可以打开网页、读 DOM、点击、输入、执行 JS、截图、管理多标签、读取历史、验证 Cookie 是否存在、把网页截图推送到文件托盘。`codex-browser` 请求写入队列，多个命令不会互相覆盖；每个请求会写入独立 `results/<request_id>.status/json`。

Cookie 边界需要注意：内嵌 WebView 的 Cookie/WebStorage 会在 App 数据目录中持久化，适合定时签到这类长期任务；但它不共享 Chrome、Edge 或 Custom Tabs 的 Cookie。遇到登录、授权、验证码或风控时，可以用 `auth-open` 先创建任务卡；用户点“打开/重开”后才切到 Custom Tabs/系统浏览器处理；用户点击“我已完成 / 取消 / 折叠 / 重开”会写入 `user_action`、`auth_state`、`needs_user`、`visible/collapsed` 等字段，Agent 不需要猜。

官方 Codex 登录建议运行：

```sh
codex 官方登录
```

该命令会调用 `codex login --device-auth`，把登录链接和一次性验证码交给安全登录任务卡；完成后用 `codex login status` 验证，不会打印 token、Cookie 或 `auth.json` 内容。

会话时间线用于承载 Agent 的思考、工具、长文本、文件和浏览器协作摘要。整体折叠只隐藏托盘列表，不会清空记录；清空才会删除时间线记录：

```sh
codex-session start --run run-1 处理任务
codex-session add tool --run run-1 --title 命令 --summary 成功
codex-session timeline collapse 已收起
codex-session timeline expand 继续查看
codex-session status
codex-session events
```

RTK 用来减少之后的 shell 输出噪音。它不会删除已经出现在终端或 Codex 上下文里的历史内容。2.0.8 起普通启动 `codex` 会在启动前询问快捷授权；选择 `1` 后会写入系统级托管 hooks，不需要再进入 `/hooks`。手动检查命令：

```sh
codex-rtk status
codex-rtk verify
codex-rtk disable
```

临时跳过 RTK hook：

```sh
RTK_DISABLED=1 git status
```

上下文压缩监测：

```sh
codex-context status
codex-context events
codex-context verify
codex-context disable
```

`codex-context` 会记录 `PreCompact`、`PostCompact` 和 `SessionStart` 事件。它只写入 `~/.codex/context-state/` 和 App 的会话事件流，不会阻止 Codex 自动压缩，也不会读取或上传密钥。

安装器还会创建多种大小写入口，例如：

```sh
codex
Codex
CODEX
```

这对手机软键盘输入很有用。

## AGENTS.md

当前版本不再由安装器创建、复制或覆盖 `AGENTS.md`。如果你需要给某个项目添加 Codex 工作规则，请进入目标目录后在 Codex 里运行：

```text
/init
```

然后按 Codex 官方流程编辑该目录下的 `AGENTS.md`。更新脚本、配置模式和普通启动都不应该改动用户自己写的 `AGENTS.md`。

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
- 首次安装或显式 `codex-update apply` 时下载的脚本模块。

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
codex-local doctor
```

如果提示启动器缺失，可以运行 `codex-local repair-launcher`。需要管理第三方 API、切换配置或修复全权限授权时运行 `codex 配置模式`。

**下载 Codex 压缩包很慢或失败？**

Codex 压缩包在 GitHub Release。建议开启代理/VPN 后重新打开 App，安装器会尽量继续已有下载。

**第三方 API 配置失败？**

确认服务兼容 OpenAI Responses API，并测试 `/models`：

```sh
curl -v --http1.1 https://api.example.com/v1/models
```

如果返回 `401`，通常说明网络通了，但缺少 Authorization；如果连不上，多半是 Base URL、代理或服务端兼容性问题。

**Codex 结束时出现 hook 相关错误？**

2.0.8 起配置模式默认写入：

```toml
[features]
hooks = true
```

如果你迁移过旧配置，运行 `codex` 并在启动前选择 `1. 快捷授权并启动 Codex`。脚本会把 RTK/context 写入系统级 `requirements.toml`，并清理 `~/.codex/config.toml` 里的旧 Codex for TUI 用户级 hook 块；用户自己的 hooks 不会被授权或删除。`codex-rtk disable` 或 `codex-context disable` 只用于移除用户级手动 hook 配置。

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

维护脚本时要注意：`android-arm64-musl/` 下的脚本是主要维护源。APK assets 里只同步薄 bootstrap；普通启动不更新脚本，只有首次安装或显式 `codex-update` 才拉取远端脚本。

## 构建与验证

本仓库使用 GitHub Actions 构建 release APK。构建前会先运行安装器 smoke test 和静态门禁，覆盖 bootstrap 不自动联网、显式脚本更新、本地启动器不 preflight、模型目录显式刷新、bridge/浏览器/发布签名等路径。

本地建议先跑脚本级测试：

```sh
git diff --check
sh tests/codex-for-tui-installer-smoke.sh
sh tests/codex-for-tui-static-guards.sh
sh -n tests/codex-for-tui-device-smoke.sh
sh -n tests/codex-for-tui-browser-smoke.sh
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
