# Changelog

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
