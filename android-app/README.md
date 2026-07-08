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
codex 上下文监测
codex-update check
codex-update apply
codex-local refresh-models
```

`codex 更新` 只增量更新脚本，不重装依赖、不替换 Codex 二进制；`codex 配置模式` 打开配置管理器，支持配置增删改查、切换和未保存保护：新建或编辑后会主动询问保存，切换或退出前会提示保存未保存修改。`codex 上下文监测` 会调用 App 内置 `codex-context status`，查看 token_count、context_compacted 记录和压缩路线推断。安装器不管理 `AGENTS.md`，需要项目规则时请在 Codex 内运行 `/init`。

## 文件面板

测试包内置原生文件面板。终端内运行：

```sh
codex-preview /path/to/image.png
codex-preview /path/to/notes.md
codex-preview --background /path/to/video.mp4
printf '很长的文本\n' | codex-preview text --stdin --name notes.txt
codex-push-image /path/to/image.png
codex-push-media /path/to/video.mp4
codex-preview path 1783070528.24966
codex-preview status
codex-preview events
codex-preview close
```

命令会把图片、视频或文本复制到 App 私有目录。默认展示内嵌文件容器；带 `--background` 时只加入托盘不展开。
多次推送会累积为缩略图文件面板；面板第一格常驻文本框，用户发送后会保存为文本引用并清空输入框。图片点击后进入全屏缩放预览，多张图片可左右滑动查看，视频使用系统级 Media3 控件播放，文本文件只展示摘要，不把全文刷到终端。文件面板内也可以通过系统文件管理器选择文本、图片或视频。发送文件时可以附加一句话，终端只显示短文件编号；AI 需要真实路径时可运行 `codex-preview path <编号>` 解析。折叠、删除、清空、发送等用户动作会写入 `status/events`，供终端侧继续协作。

## 浏览器

终端内运行：

```sh
codex-browser --no-wait open 'https://example.com'
codex-browser status
codex-browser present 页面已就绪
codex-browser user-wait 请完成验证
codex-browser status
codex-browser events
codex-browser list-tabs
codex-browser new-tab https://example.com/help
codex-browser cookies verify https://example.com
codex-browser screenshot --push
codex-browser auth https://chatgpt.com
codex-browser external https://example.com/login
codex-browser auth-open --reason "Codex 官方登录" --code "ABCD-EFGH" https://chatgpt.com/activate
# 如确实需要立即跳系统浏览器：codex-browser auth-open --open-now --reason "登录" https://example.com/login
codex-browser auth-wait '<request_id>'
```

`open` 使用 App 内嵌 WebView，默认后台加载，适合读取 DOM、点击、输入和截图；需要展示给用户时调用 `present`，需要用户协作时调用 `user-wait`（也兼容 `wait-user`）。浏览器请求写入队列，多个 Agent 命令不会互相覆盖；每个请求都有独立 `results/<request_id>.status/json`。

内嵌 WebView 支持多标签、历史记录、Cookie 状态/验证、WebStorage 持久化、WebView 自绘截图和本地 userscript 注入。`screenshot --push` 会把当前网页截图加入可清理文件托盘，可用 `codex-preview path <编号>` 解析真实图片路径。`cookies status|verify` 不输出 Cookie value，只输出 Cookie 名称和数量。

`auth-open` 默认只创建 App 内安全登录任务卡，用户点“打开/重开”或使用 `--open-now` 才会打开 Chrome Custom Tabs 或系统浏览器；旧 `auth` / `external` 仍保持立即打开兼容，适合登录、授权、验证码和风控场景；该模式不向 App 暴露用户浏览器 Cookie。Auth 任务卡会把用户点击“我已完成 / 取消 / 折叠 / 重开”的动作写回 `results/<request_id>.status/json` 和统一事件流，字段包括 `auth_state`、`user_action`、`needs_user`、`visible`、`collapsed`。需要定时签到或自动化复用登录态的站点，应在内嵌 WebView 中完成一次登录；Android WebView 的 Cookie 不与 Chrome、Edge 或 Custom Tabs 共享。

官方 Codex 登录建议运行 `codex 官方登录`。启动器会调用 `codex login --device-auth`，解析登录链接和一次性验证码并创建安全登录任务卡；用户可在卡片中点击“打开/重开”进入 Custom Tabs；用户完成后再用 `codex login status` 验证，不打印 token、Cookie 或 `auth.json` 内容。

2.3.1 新增 `codex-doctor`、`codex-clean`、`codex-ops`：`codex-doctor` 做只读环境诊断，`codex-clean scan` 默认只扫描，`codex-clean apply` 只移动到 `$PREFIX/local/ops/trash/<task_id>/`，`codex-clean restore` 可恢复，`codex-ops status/events/resume-hint` 用于断线后续连排障。所有运维输出默认脱敏，不打印 token、Cookie、API key 或 `auth.json` 内容。

2.2.9 修复 2.2.8 真机复测仍失败的后台 WebView 截图空图问题，折叠状态下会把 capture host 挂到 App 内容背后，并启用 `enableSlowWholeDocumentDraw`、等待渲染帧、WebView `onDraw`、`capturePicture` 和 DOM 文本快照兜底，不自动展开托盘；2.2.7 修复 `codex-browser js` 裸表达式返回值、Auth 取消状态残留和 RTK/context 系统托管 hook 状态显示；2.2.5 起 RTK hook 会把 `rtk ...` 改写为 App 内置 RTK 的绝对路径，并跳过复杂 `find` 改写，避免登录 shell `PATH` 缺失时出现 `rtk: not found` 或 `rtk find` 不支持参数导致命令失败；2.2.3 起打开 Custom Tabs/外部浏览器后，文件托盘、浏览器和 session fold bridge 不会因为 Activity 进入后台而停止消费 Agent 请求；2.2.2 起终端输出刷新会按屏幕帧合并，Compose 托盘/浏览器/session fold 状态更新会尽量去重，bridge 请求优先由文件事件触发并保留低频兜底轮询；排障状态写入 `$PREFIX/local/perf/terminal.status`。2.2.1 起 `auth-open` 默认不再自动跳出，2.2.0 起浏览器桥支持 Auth Browser 任务、外部 scheme 打开确认、验证码/风控状态字段和更明确的折叠/完成/取消事件。2.1.3 起浏览器桥对单个坏请求做异常隔离，队列请求先完成 legacy request 再暴露给 App 消费；页面加载会等待 userscript 注入回调后再向终端返回 `open` 完成。userscript 注入使用延迟重试、回调解析和本地 `userscripts.log`，注入失败会反馈给 `codex-browser`，避免 `open -> get-text` 抢跑或静默失败。

## 构建

推荐使用仓库的 GitHub Actions 构建 release APK。构建前会先运行安装器 smoke test。2.x 正式 APK 签名证书 SHA-256 固定为 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`，release 构建会校验该指纹，避免误换签名导致用户无法覆盖升级。

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
