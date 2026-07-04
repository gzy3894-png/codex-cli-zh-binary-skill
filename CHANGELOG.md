# Changelog

## Codex for TUI 2.0.8

Codex for TUI 2.0.8 修复 RTK 默认启用、会话托盘耗时刷新和上下文压缩监测三类问题，让长会话在自动 compact 前后更容易交接。

### 新功能

- 新增 `codex-context status|events|hook|enable|disable|verify`，默认配置 `PreCompact`、`PostCompact` 和 `SessionStart(startup|resume|compact)` hook。
- `codex-context` 会把自动/手动 compact 事件写入 `~/.codex/context-state/`，并追加到 App 会话事件流，后续 Agent 可用 `codex-context events` 或 `codex-session events` 追踪。

### 修复

- 配置模式默认写入 `hooks = true`，并保持 Codex for TUI 托管的 RTK/context hook；新建、编辑或切换第三方配置后不再丢失 RTK。
- 会话托盘运行中耗时改为 UI ticker 自动刷新，不再依赖 Agent 主动传参，也不会每秒写状态文件。

### 验证与回滚

- 本地非 APK 门禁要求：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`、RTK/context hook 样例输入测试。
- APK、签名校验、RTK 二进制和 release 资产仍只通过 GitHub Actions 构建。
- 完整源码由 tag `codex-for-tui-v2.0.8` 固定保存；本轮实施前回滚锚点为 `rollback/2.0.7-before-2.0.8-5cac3a8` 和 `rollback-2.0.7-before-2.0.8`。

## Codex for TUI 2.0.7

Codex for TUI 2.0.7 内置 RTK，并补齐会话托盘总折叠能力，重点减少之后 shell 输出刷屏，同时让 Agent 能明确感知会话时间线是否折叠。

### 新功能

- 内置 RTK `v0.43.0`，由 GitHub Actions 构建 `aarch64-unknown-linux-musl` 二进制并随 APK 同步到终端环境。
- 新增 `codex-rtk status|enable|disable|verify|hook`，可显式检查 RTK、启用/关闭 Codex PreToolUse hook，并保留 `RTK_DISABLED=1` 临时跳过。
- `codex-rtk enable` 只追加 Codex for TUI 管理的 hook 块，并会备份 `~/.codex/config.toml`；`disable` 只移除托管块，不删除用户自己的 hooks 或配置。
- 会话时间线新增总折叠：`codex-session timeline collapse|expand|toggle [REASON]`。
- `codex-session status/events/result` 新增 `timeline_collapsed=0|1`，用户点击折叠/展开会写入 `user_timeline_collapsed` / `user_timeline_expanded`，Agent 命令会写入 `agent_timeline_collapsed` / `agent_timeline_expanded`。

### 体验优化

- 会话时间线 header 更紧凑，显示会话摘要和 `runs/items` 数量。
- 总折叠只隐藏列表，不清空 run/item 记录；清空仍是独立操作。
- RTK 只压缩之后进入 Codex 的 shell 输出，不会删除已经存在的终端文本或历史上下文。

### 验证

- 本地非 APK 门禁通过：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`、RTK hook 样例输入和配置保留测试。
- GitHub Actions 分支构建通过：脚本静态检查、RTK ARM64 musl 构建、qemu 验证和 test APK。
- 正式 APK、签名校验和 release 资产仍只通过 GitHub Actions tag/release 构建。

### 回滚

- 完整源码由 tag `codex-for-tui-v2.0.7` 固定保存，GitHub Release 会自动保留 source zip/tar。
- 回滚到 2.0.6 可安装 release `codex-for-tui-v2.0.6` 的 APK，源码 tag 为 `codex-for-tui-v2.0.6`。
- 本轮功能基线保留在分支 `rollback/rtk-session-fold-base-65f7c28`。

## Codex for TUI 2.0.6

Codex for TUI 2.0.6 新增会话折叠 v1，让 Agent 过程信息进入 App 原生结构化时间线，而不是完整刷进终端文本。

### 新功能

- 新增 `codex-session` 桥接命令，支持 `start/add/done/fail/expand/collapse/remove/clear/status/events/wait/result`。
- 新增会话折叠时间线：思考、工具、文本、文件、浏览器和最终结果可归入同一个 run，完成后默认折叠为“已处理 <耗时>”。
- 用户展开、折叠、删除和清空会话折叠项会写入 `session-fold/events`，Agent 可以通过 `codex-session events/wait` 感知。
- 文件托盘、长文本发送和浏览器协作会在存在 active session run 时附加到当前折叠记录；旧 `codex-preview`、`codex-browser`、`codex-panel` 用法保持兼容。

### 验证

- 本地非 APK 构建门禁：静态 guards、APK asset shell 语法和 `git diff --check`。
- APK 构建、签名校验和 release 资产仍只通过 GitHub Actions 完成。

## Codex for TUI 2.0.5

Codex for TUI 2.0.5 修复 2.0.4 安装后运行时调试发现的 Agent 面板协议字段一致性问题。

### 修复

- 文件托盘后台加入图片、视频或文本时，`codex-panel status files` 会立即带上 `item_id`、`name`、`stamp`，不必等到 `present` 后才能拿到编号。
- 文件删除后的 `result` 不再把被删除项继续写成 `active_item`，避免 Agent 误判当前仍选中旧文件。
- 浏览器 `status` 和 `result` 补齐 `active_item`、`tab_id`、`tabs_count`、`visible`、`collapsed` 等字段，和统一事件流保持一致。
- 显式 `present` / `user-wait` 会在处理请求前先标记浏览器面板展开，避免 `browser_needs_user` 事件先出现一条错误的 `visible=0`。

### 验证

- 本地非 APK 构建门禁：静态 guards、APK asset shell 语法、脚本库 `sh -n` 和 `git diff --check`。
- APK 构建、签名校验和 release 资产仍只通过 GitHub Actions 完成。

## Codex for TUI 2.0.4

Codex for TUI 2.0.4 完整化 Agent 面板双向协议，让文件托盘和协作浏览器都能被 Agent 稳定控制，也能把用户操作结构化回传给终端侧。

### 新功能

- 新增统一 `codex-panel` 命令：支持 `status/events/wait/result`，以及对 `files`、`browser` 的 `present`、`collapse`、`toggle`、`done`、`cancel`、`clear/close`、`select/remove` 等操作。
- `codex-preview` 兼容新增 `present`、`collapse`、`toggle`、`done`、`cancel`、`result`、`select/remove`，继续保留图片、视频、文本推送和短编号路径解析。
- `codex-browser` 兼容新增 `collapse`、`toggle`、`done/cancel`、`result`，浏览器托盘折叠和用户协作完成都能被 Agent 明确感知。
- 用户侧动作会写入统一事件字段：`visible`、`collapsed`、`request_id`、`item_id`、`active_item`、`reason`，并附带文件类型、路径、浏览器 URL、标题、标签数、是否等待用户等参数。

### 修复

- 浏览器标签选择/关闭改为通过 `MainActivity` 回写事件，不再由 UI 直接调用底层会话方法后让 Agent 猜状态。
- 文件预览打开、关闭、长按分享、系统文件选择器打开/取消/失败、用户发送文件/长文本都会同步写入事件流。
- 文本文件继续归入 `files` 面板源，用 `kind=text` 区分，避免出现 `codex-panel status files|browser` 之外的第三种面板源。
- 更新脚本生成的桥接 wrapper 包含 `codex-panel`，减少 resume/旧 PATH 环境下命令不可见的问题。

### 验证

- 本地非 APK 构建门禁：APK asset shell 语法、`codex-panel` 请求写入、文件/浏览器桥接静态 guards 和 `git diff --check`。
- APK 构建、签名校验和 release 资产仍只通过 GitHub Actions 完成。

## Codex for TUI 2.0.2

Codex for TUI 2.0.2 修复正式包自测中发现的桥接命令入口和浏览器协作状态问题。

### 修复

- 新增 `codex-preview`、`codex-push-image`、`codex-push-media`、`codex-browser` 的安装目录包装入口；即使当前 Codex 会话没有继承 App 的 `$PREFIX/local/bin`，Agent 和用户也能直接调用裸命令。
- `codex` 启动器会在运行时识别 App 桥接命令目录，并把它加入 PATH，减少 resume/旧会话环境下的命令不可见问题。
- `codex-browser user-done` 和 `user-cancelled` 现在会同步收起浏览器托盘并写入面板事件，避免 Agent 只能看到 `needs_user=0` 却无法判断托盘是否已经结束接管。

### 验证

- 本地非构建门禁：APK asset shell 语法、静态 guards 和脚本语法检查。
- 已在正式包数据目录中手动验证裸 `codex-browser`、`codex-preview`、图片/视频/文本托盘、浏览器静默打开、展示和关闭信号。
- APK 仍只通过 GitHub Actions 构建发布。

## Codex for TUI 2.0.1

Codex for TUI 2.0.1 修复 2.0 正式版后续测试中发现的浏览器和文件托盘协作问题。

### 修复

- `codex-browser open` 继续默认后台打开；当手机终端误把 `codex-browser status` 粘在同一行时，不再直接 usage 失败，而是继续发送打开请求并提示 `status` 需要另起一行执行。
- 浏览器协作命令支持 `user-wait` 和 `wait-user` 两种写法，便于 Agent 和用户按自然语序调用。
- 文件托盘发送文本/文件到当前会话时，终端提示进一步缩短为编号和 `codex-preview path <编号>`，避免长提示词干扰 shell 或 Codex 上下文。
- README 和 Android README 的浏览器测试命令改为 URL 加引号、`status` 单独执行，更适合手机终端复制粘贴。

### 验证

- 本地非构建门禁：APK asset shell 语法、安装器 smoke test、静态 guards 和 `git diff --check`。
- GitHub Actions：测试 APK 由仓库工作流构建通过；正式 APK 由 release/tag 工作流构建。
- 2.x 正式 APK 签名证书 SHA-256 固定为 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`；后续 release 构建会校验该指纹，避免误换签名导致用户无法覆盖升级。

## Codex for TUI 2.0.0

Codex for TUI 2.0.0 聚焦移动端协作体验：文件托盘、协作浏览器和更轻的顶部容器。

### 新功能

- 新增文件托盘：支持在终端中用 `codex-preview <path>` 推送图片、视频和文本到顶部容器，也支持 `--background` 后台加入托盘。
- 文件托盘第一格常驻文本框，用户发送长文本后保存为文本引用并清空输入框。
- 支持用户从 Android 系统文件管理器添加文件，并在文件卡片里预览、删除或发送到当前 Codex 会话。
- 文件发送支持附加说明，适合把截图、视频、长文本和一句用户描述一起交给 AI。
- 终端文件提示改为短编号和 `codex-preview path <编号>`，避免刷出完整应用私有路径。
- 新增协作浏览器托盘：`codex-browser open` 默认后台加载，`present` / `user-wait`（兼容 `wait-user`）才展示给用户；支持页面打开、DOM 读取、点击、输入、执行 JS、截图和用户接管。
- 新增统一面板信号：`status/events/wait` 可回传折叠、完成、取消、删除、清空、发送等用户事件。
- 浏览器支持多标签底层能力，并在托盘顶部显示紧凑标签条，可切换和关闭标签。
- WebView 文件上传会调用系统文件选择器；登录、授权、验证码和风控场景可切到 Custom Tabs 或系统浏览器处理。

### 体验优化

- 顶部“文件”和“浏览器”入口按钮进一步缩小，减少占用标题栏空间。
- 文件托盘和浏览器托盘背景透明度降低，终端上下文更容易保留在视野里。
- 文件托盘不会自启动展开，清空/删除会同步清理内部引用。
- 长文本文件只进入托盘和引用，不再把完整内容刷到终端屏幕。
- 浏览器和文件托盘不再因为后台操作自动弹出，减少 Agent 自动化时对用户终端的遮挡。

### 验证

- 本地脚本门禁：安装器 smoke test、静态 guards、设备 smoke 脚本语法、APK asset shell 语法和 `git diff --check`。
- GitHub Actions 构建：正式 APK 由仓库工作流构建。
- Android emulator smoke：覆盖浏览器桥接、用户接管、文件托盘缩略图、发送说明、短文件引用和系统文件选择器。
