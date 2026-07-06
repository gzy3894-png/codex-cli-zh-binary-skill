# Changelog

## Codex for TUI 2.2.5

Codex for TUI 2.2.5 是 2.2.4 发布前追加的 RTK 安全热修版：保留 RTK 绝对路径修复，同时避免把复杂 `find` 命令错误改写成 `rtk find`。

### 修复

- `codex-rtk hook` 遇到带 `-exec`、`-execdir`、`-ok`、`-delete`、`-not`、`-o`、`-a`、括号或 `!` 的复杂 `find` 命令时直接 fail-open，保留原命令执行。
- 保留 2.2.4 的绝对路径修复：RTK 改写结果中的 `rtk ...` 会转为 App 内置 RTK 二进制路径，避免 `PATH` 缺失导致 `rtk: not found`。
- 静态门禁新增复杂 `find` 不改写检查，避免后续回退。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：登录 shell 下 `git status` 等 RTK 改写命令使用绝对路径；复杂 `find ... -exec ...` 不被 RTK 改写，避免命令失败。

## Codex for TUI 2.2.4

Codex for TUI 2.2.4 是 2.2.3 的 RTK hook 热修版，重点修复少数登录 shell 环境下 `PATH` 不含 `$PREFIX/local/bin` 时，RTK 改写后的命令可能报 `rtk: not found` 的问题。

### 修复

- `codex-rtk hook` 现在会把 RTK 改写结果中的 `rtk ...` 转为当前 App 内置 RTK 二进制的绝对路径，避免依赖用户 shell 的 `PATH`。
- hook 会识别已经使用绝对路径的 RTK 命令并直接跳过，避免二次改写或循环。
- 静态门禁新增绝对路径检查，确保后续不会退回裸 `rtk ...`。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：登录 shell 下即使 `command -v rtk` 为空，RTK hook 也能返回 `$PREFIX/local/bin/rtk ...` 绝对路径，终端命令不再报 `rtk: not found`。

## Codex for TUI 2.2.3

Codex for TUI 2.2.3 是 2.2.2 的真机门禁热修版，重点修复打开 Custom Tabs/外部浏览器后 bridge 停止消费的问题。

### 修复

- 文件托盘、协作浏览器和 session fold bridge 不再在 `MainActivity.onStop()` 时停止；Activity 被 Custom Tabs/系统浏览器盖到后台时仍可消费 Agent 写入的请求。
- bridge 观察器和 fallback poll 改为 Activity 销毁时才停止，避免 Auth Browser 折叠/完成/取消、外部 scheme 协作、文件托盘和会话折叠状态卡在旧请求。
- `onResume` 继续主动轮询文件托盘、浏览器和 session fold 请求，回到终端后能尽快补处理积压事件。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：覆盖 2.2.2 高频输出门禁，并重跑 Custom Tabs/Auth Browser 返回后 bridge 继续消费、外部 scheme、文件托盘、session fold、Cookie/localStorage、截图推送和旧命令兼容。

## Codex for TUI 2.2.2

Codex for TUI 2.2.2 是终端流畅度优化版，重点减少长输出、托盘状态刷新和 bridge 轮询叠加造成的卡顿。

### 优化

- 终端输出刷新按屏幕帧合并，避免每次文本变化都立即触发 `TerminalView` 重绘。
- Compose 层不再因普通重组无条件刷新终端；托盘、浏览器和会话折叠状态尽量结构相等去重。
- 文件托盘、浏览器和 session fold bridge 优先由文件事件触发，保留低频 fallback poll，减少空轮询。
- 新增 `$PREFIX/local/perf/terminal.status` 轻量排障状态，便于确认合帧和 bridge 工作模式。
- 持久化 `/root/AGENTS.md` 子代理路由约定：复杂跨模块任务用主代理总控、`explorer` 只读探索、`worker` 分片实现。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：`seq 1 5000`、`yes | head -n 5000` 高频输出，输入/复制粘贴/软键盘/虚拟键/切 session，文件/浏览器/会话托盘，bridge 事件，以及 2.2.1 Auth Browser 回归。

## Codex for TUI 2.2.1

Codex for TUI 2.2.1 是 2.2 浏览器协作体验热修版，重点减少 Auth Browser 对用户前台页面的打断。

### 修复

- `codex-browser auth-open` 默认只创建 App 内安全登录任务卡，不再自动跳出到 Custom Tabs/系统浏览器，避免 Agent 测试或重试时反复弹外部页面。
- 需要立刻打开系统浏览器时可显式使用 `codex-browser auth-open --open-now ...`；用户也可以在任务卡里点“打开/重开”，Agent 侧仍可用 `auth-reopen <request_id>`。
- 旧 `codex-browser auth URL`、`external URL`、`custom-tab URL` 保持立即打开兼容，避免破坏已有脚本。
- 官方登录向导继续创建 Auth 任务卡并展示一次性 code；用户确认后再从卡片进入 Custom Tabs，脚本仍用 `codex login status` 验证，不打印 token/Cookie/auth.json。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：`auth-open` 不自动弹外部浏览器，`auth-reopen/打开按钮` 才打开；完成/取消/折叠/重开继续写回结构化字段。

## Codex for TUI 2.2.0

Codex for TUI 2.2.0 聚焦浏览器协作：把登录/授权/验证码交给调用式 Custom Tabs Auth Browser，同时继续增强内置 WebView Agent Browser。

### 新增

- `codex-browser auth-open/auth-wait/auth-status/auth-done/auth-cancel/auth-reopen`：打开安全登录任务卡，用户完成、取消、折叠、重开都会写回 `user_action/auth_state/visible/collapsed`。
- `codex 官方登录`：调用 `codex login --device-auth`，解析登录链接和一次性验证码，通过 Custom Tabs 打开，完成后用 `codex login status` 验证。
- 外部 scheme 打开确认：`intent://`、`mailto:`、`tel:`、`baiduboxapp://` 等不再直接跳走，先让用户确认，并写回确认/取消事件。

### 增强

- WebView Agent Browser 增加验证码/风控检测字段：`risk_challenge_detected`、`risk_challenge_kind`、`recommended_next_action`。
- Auth Browser 不读取 DOM、密码、Cookie 或 `auth.json`；结果和日志只记录用户动作、链接、一次性 code 和状态，不打印 token/Cookie。
- 保持旧 `codex-browser open/status/screenshot/auth/external/user-wait` 用法兼容。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 正式发布前必须真机验证 auth-open 用户动作回传、Codex device-auth 登录向导、WebView 静默/展示、多标签事件、风控 needs_user、外部 scheme 确认、Cookie/localStorage 持久化、截图推送和旧命令兼容。

## Codex for TUI 2.1.3

Codex for TUI 2.1.3 是 2.1.2 的真机热修版，重点修复协作浏览器 userscript 自动注入在后台 WebView 场景下可能静默失败的问题。

### 修复

- `codex-browser open` 等待 userscript 注入完成；如果注入超时或执行失败，会把错误返回给终端，不再误报页面已可用。
- userscript 注入改为延迟重试，并通过 `new Function(...)` 隔离执行脚本内容，降低脚本内容破坏注入包装器的概率。
- 注入回调会解析执行结果，并写入本地 `local/browser/userscripts.log`，便于真机排查是匹配、执行还是 WebView 回调问题。
- userscript match 支持多条规则和通配符，保留裸字符串 contains 匹配兼容旧命令。
- README 修正已安装用户更新说明：覆盖 APK 不会自动联网刷新 `~/.local/share/codex-zh/scripts`；需要配置管理器脚本时请显式运行 `codex 更新 && codex-local repair-launcher`。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 覆盖安装后必须再次运行 `tests/codex-for-tui-browser-smoke.sh` 真机验证 userscript、多标签、队列、Cookie/WebStorage、截图推送和接管状态。

## Codex for TUI 2.1.2

Codex for TUI 2.1.2 把配置管理器修复合入正式版，不需要先安装 2.1.1。全新安装会拉取最新脚本；已安装用户覆盖 APK 后，如需刷新 `~/.local/share/codex-zh/scripts` 里的配置管理器脚本，仍应显式运行 `codex 更新 && codex-local repair-launcher`。

### 修复

- `codex 配置模式` 改为配置管理器，围绕配置的增、删、改、查和切换工作。
- 新建或编辑第三方 API 配置后主动询问是否保存为配置档，不再要求用户事后手动选择“保存当前配置”。
- 切换配置或退出配置模式前，如果当前配置有未保存修改，会先提示保存、另存或放弃，避免配置档为空或丢失。
- 已保存配置支持查看和删除；空列表、错误编号、取消删除等操作都会返回当前菜单，不再直接退出整个配置模式。
- 切换旧配置时会补齐 `approval_policy = "never"`、`sandbox_mode = "danger-full-access"` 和 hooks，避免授权或 RTK/context 设置丢失。

### 验证

- 新增配置菜单 smoke：自动保存新配置、切换前保存未保存修改、空列表/错误输入不退出、删除可取消。
- 本地门禁仍只运行 shell/static 测试，不运行本地 Gradle/APK 构建。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。

## Codex for TUI 2.1.1

Codex for TUI 2.1.1 是 2.1.0 协作浏览器硬化后的热修版，重点修复真机 smoke 中发现的队列竞态、桥接轮询退出和 userscript 注入抢跑问题。

### 修复

- `codex-browser` 写请求时先准备 legacy request，再暴露队列文件，避免 App 抢先消费队列后 shell 侧复制失败。
- 浏览器桥轮询加入顶层异常保护和单队列文件异常隔离，单个坏请求不会让后台桥接协程停止消费后续请求。
- 页面 `onPageFinished` 后等待 userscript 注入回调再完成 `open` 请求；`get-text #selector` 对短暂异步渲染/注入增加小轮询。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 覆盖安装后需再次运行 `tests/codex-for-tui-browser-smoke.sh` 真机验证多标签、队列、Cookie/WebStorage、截图推送、userscript 和接管状态。

## Codex for TUI 2.1.0

Codex for TUI 2.1.0 硬化协作浏览器，并加入终端默认背景图，让 WebView 自动化更接近长期可用。

### 新功能

- `codex-browser` 改为队列请求，避免并发命令覆盖同一个 request 文件；每个请求写入独立 `results/<request_id>.status/json`。
- 浏览器补齐多标签列表、选择/关闭、历史记录、Cookie 状态/验证、Cookie flush、WebView 自绘截图推送文件托盘。
- 新增本地 userscript 注入：从本地文件导入，按 URL match 注入，不自动下载远程脚本。
- 内置终端预设背景图，默认透明度为 1；用户自定义背景仍然优先。

### 边界

- 内嵌 WebView 的 Cookie/WebStorage 会持久化，但不与 Chrome、Edge 或 Custom Tabs 共享。
- `cookies status|verify` 只返回 Cookie 名称和数量，不输出 Cookie value。
- Chrome/Edge 原生扩展不适用于 Android WebView；本版本以 userscript 作为可控替代。

### 验证

- 本地非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- 新增 `tests/codex-for-tui-browser-smoke.sh`，用于真机测试多标签、请求队列、Cookie、localStorage、历史、截图推送、userscript 和用户接管状态。
- APK、签名校验、RTK 二进制和 release 资产仍只通过 GitHub Actions 构建。

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
