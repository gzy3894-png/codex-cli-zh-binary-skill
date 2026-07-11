# Codex for TUI

[![Release](https://img.shields.io/badge/release-v2.4.5-blue)](https://github.com/gzy3894-png/codex-cli-zh-binary-skill/releases/tag/codex-for-tui-v2.4.5)
[![Codex](https://img.shields.io/badge/Codex%20CLI-0.144.1-111827)](./android-arm64-musl/README.md)
[![Target](https://img.shields.io/badge/target-android%20arm64%20musl-0f766e)](./android-arm64-musl/README.md)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](./LICENSE)

Codex for TUI 是一个面向 Android 手机的 Codex CLI 终端应用。它基于 ReTerminal 改造，内置 Alpine/proot 终端环境、Codex 中文版 ARM64 musl 安装流程、文件托盘和协作浏览器，让用户不必先手动折腾 Termux、rootfs、依赖、PATH、API 配置、本地维护命令和移动端预览工具。

一句话：安装 APK，打开终端，按提示完成依赖和 API 配置，就可以在手机上进入 Codex TUI。

## 重要：2.4.5 冷启动体验（基于 2.4.2 完整环境升级）

2.4.5 默认进入 shell（不再自动 `exec codex`），设置页可开启「启动时自动进入 Codex」；过滤 proot 绑定警告，工作目录改为 `/root/workspace` 以减少 project-local 黄色配置提示；日常冷启动在升级已完成后静默秒退。配置档仍按 profile 隔离，压缩默认 follow-model。2.4.4 的文件托盘「附加说明」与 2.4.3 的 `tool_mode` 修复继续保留。发布说明见 `docs/codex-for-tui-2.4.5-release-notes.md`。

2.4.2 把 APK 覆盖安装升级为离线、原子、可回滚的完整用户环境升级。老用户安装 APK 并打开 App 后，会在 Codex 启动前自动校验并安装固定 `0.144.1-zh.1` 二进制、launcher、配置引擎和受管脚本，迁移 V1/V2 配置，以 `/root/.codex/config.toml` 为活动配置，重建与 `rust-v0.144.1` 一致的模型目录，并为每个站点隔离 runtime、sessions 和 SQLite。全新 rootfs 缺少 Python 时，会在首次安装确认后自动补齐 `python3` 再继续；单次启动最多尝试 3 次，连续失败会阻止 Codex 启动并在下次打开时重试。升级失败会回滚并阻止 Codex 启动，下次打开自动重试。无需手动运行 `codex 更新`、`codex-local repair-launcher`、配置模式或 `CODEX_HOME=...`。发布说明见 `docs/codex-for-tui-2.4.2-release-notes.md`。

2.4.1 修复 2.4.0 的配置与模型回归：配置模式返回或迁移失败后只退出到 shell，不再继续启动 Codex；旧配置迁移不再遍历 SQLite、sessions、FIFO 和插件临时对象；每个配置使用独立 config/auth/session/runtime，SQLite 再按 Codex 版本与二进制 SHA 隔离，避免不同站点并行会话互相覆盖和 SQLx migration checksum mismatch。模型能力固定到 Codex `0.144.1` 对应的 `rust-v0.144.1` 目录；生成目录会隐藏 `codex-auto-*` 辅助模型，使现有 Codex 原生 `/model` 直接进入完整可选模型页，推理等级与该构建的上游目录一致。发布说明见 `docs/codex-for-tui-2.4.1-release-notes.md`。

2.4.0 重构了配置档、模型目录和上下文策略底层，并将随包中文 Codex CLI 升级到 `0.144.1`：配置模式改为扁平 CRUD，配置档使用稳定 ID 和事务写入，TOML 注释与未知字段会保留；旧配置可无损迁移并完整回滚。第三方 `/models` 只决定可用模型 ID，推理等级、上下文窗口和工具能力从 OpenAI Codex 官方目录精确合并，支持 `max` / `ultra`、未知模型保守模式和“跟随模型 / 固定 token”压缩策略。发布说明见 `docs/codex-for-tui-2.4.0-release-notes.md`。

2.3.11 是 2.3.10 的文件托盘桥接竞态热修版：修复 `codex-preview clear` / `codex-panel clear files` 等控制请求在 App 快速清理 `queue/` 时，shell 端临时 `.req` 还没发布完成就被删掉，导致 installed smoke 出现 `mv ... No such file or directory` 的问题。发布说明见 `docs/codex-for-tui-2.3.11-release-notes.md`。

2.3.10 是 2.3.9 的文件托盘缓存生命周期热修版：App 退出重进、进程重启或覆盖安装后，会恢复仍有效的托盘临时图片/视频/文本/浏览器截图，并清理孤儿缓存；“清空”、单删、Agent clear 和自动淘汰都会同步删除 App 本地临时副本，避免 UI 空了但文件残留不可见。发布说明见 `docs/codex-for-tui-2.3.10-release-notes.md`。

2.3.9 是 2.3.8 的文件托盘热修版：文本托盘和文件卡片点“发送”后会把短引用写入当前 Codex 会话，并延迟触发真实 Enter，避免只停在输入框里等待手动提交。发布说明见 `docs/codex-for-tui-2.3.9-release-notes.md`。

2.3.8 是 2.3.7 的用户时区热修版：`codex-context report` / `codex 上下文监测` 在 Android 环境中优先使用系统时间接口格式化“几点几分”，避免 Alpine/proot 默认 UTC 导致用户侧压缩报告偏移。发布说明见 `docs/codex-for-tui-2.3.8-release-notes.md`。

2.3.7 是基于 2.3.6 稳定基线的上下文监测小版本：`codex-context` 会在 Codex hook 触发时记录本地/远程压缩来源、本会话压缩次数，并给 Agent 暴露自动压缩即将发生的准备信号；新增 `codex 上下文监测` 手机端用户报告入口。它不读取、不扫描、不改写 session/transcript 文件。发布说明见 `docs/codex-for-tui-2.3.7-release-notes.md`。

2.3.6 是安装后真机复测热修版：修复内置浏览器重复打开当前已加载根路径 URL 时，`https://example.com` 与 WebView 回调的 `https://example.com/` 被误判为不同页面，导致 `codex-browser open` 等到 `Page load timed out` 的问题。发布说明见 `docs/codex-for-tui-2.3.6-release-notes.md`。

2.3.5 是配置热修版：第三方 OpenAI-compatible 配置继续使用内部 provider id `custom`，但生成和修复后的 `[model_providers.custom].name` 会稳定写为 `OpenAI`，避免配置模式把兼容服务显示/协议名写成 `custom`。旧配置中 `name = "custom"` 会在修复全权限或重新生成配置时规范化；用户手写的 provider 名称不会被覆盖。发布说明见 `docs/codex-for-tui-2.3.5-release-notes.md`。

2.3.4 是 2.3.3 的状态字段热修版：修复 `codex-browser open` 成功后，同一个 `request_id` 的 `status/result` 被后续 WebView snapshot 回调覆盖成 `action=snapshot` 的问题。发布说明见 `docs/codex-for-tui-2.3.4-release-notes.md`。

2.3.3 是 2.3.2 的真机调试热修版：修复 `codex-browser open` 被 userscript 回调超时误判失败的问题，文件/浏览器事件流现在按 `source/mode` 严格过滤，`codex-dev-transfer export` 默认安全导出也会避开 `.codex/.tmp` 临时插件缓存，避免迁移包导出失败。发布说明见 `docs/codex-for-tui-2.3.3-release-notes.md`。

2.3.2 是 2.3.1 后的安全与稳定补丁：Release 构建继续强制 GitHub Secrets 正式签名并校验包名、版本号、非 debuggable 和正式证书；`codex-dev-transfer` 默认不迁移 `auth.json`、Cookie、WebView/db/no_backup/browser 等登录态，敏感迁移必须显式 `--include-secrets --yes`；配置/启动脚本保持“普通启动不覆盖用户配置”，并补齐 rootfs/session 生命周期稳定性门禁。发布说明见 `docs/codex-for-tui-2.3.2-release-notes.md`。

2.3.1 是 2.3.0 后的稳定底座版本：新增 `codex-doctor`、`codex-clean`、`codex-ops`，把环境诊断、可回滚清理、运维日志和断线续连提示做成 App 内置命令。新增命令的状态统一落盘到 `$PREFIX/local/ops/tasks/<task_id>/`，包含 `status`、`events`、`summary`、`resume_hint`；输出默认脱敏，不打印 token、cookie、API key 或 `auth.json` 内容。

常用入口：

```sh
codex-doctor
codex-clean scan
codex-clean apply <scan_task_id>
codex-clean restore <apply_task_id>
codex-ops status
codex-ops events
codex-ops resume-hint
```

`codex-clean scan` 默认只扫描；`apply` 只移动到 `$PREFIX/local/ops/trash/<task_id>/`，不永久删除；误清理可用 `codex-clean restore <apply_task_id>` 恢复。详细说明见 `docs/codex-for-tui-2.3.1-ops.md`，发布说明见 `docs/codex-for-tui-2.3.1-release-notes.md`。

发布安全说明：正式 APK 构建必须使用 GitHub Secrets/离线签名输入，仓库内不再提供正式 keystore fallback；Release 门禁会校验包名、版本号、非 debuggable、正式签名指纹和 APK 内离线 Codex 载荷。Android 不支持普通覆盖安装降级，2.4.5（`versionCode=60`）出现问题时只发布更高 `versionCode` 的前滚修复包。

2.3.0 是 2.2.9 后的稳定化回归版：补齐 `docs/codex-for-tui-2.3.0-regression.md` 和 `tests/codex-for-tui-installed-device-smoke.sh`，把安装/更新/首启、RTK/context、文件托盘、会话折叠、浏览器后台截图、JS、Auth 状态清理和终端性能状态纳入可重复门禁。真机回归时发现 `codex-browser open` 重复打开当前已加载 URL 可能卡到超时并误报 `Page load timed out before userscript completion`，2.3.0 已修复为直接返回当前页面快照；需要强制刷新时仍使用 `codex-browser reload`。

2.2.9 的后台 WebView 截图修复继续保留：浏览器在后台/折叠状态下执行 `screenshot --push --background` 会把 capture host 挂到 App 内容背后、启用 `enableSlowWholeDocumentDraw`、等待渲染帧，并在普通 `draw()` 后增加 WebView `onDraw`、`capturePicture` 和 DOM 文本快照兜底来截取真实网页内容，同时不自动展开浏览器托盘。

2.2.5 的 RTK hook 安全热修继续保留：`codex-rtk hook` 会把改写结果中的 `rtk ...` 转为 App 内置 RTK 的绝对路径，避免少数登录 shell 的 `PATH` 没带 `$PREFIX/local/bin` 时出现 `rtk: not found`；同时遇到复杂 `find ... -exec ...` 等 RTK 不支持的命令会直接保留原命令，避免误改写失败。2.2.3 的终端输出合帧、Compose 状态去重、bridge 低频兜底轮询，以及打开 Custom Tabs/外部浏览器后 bridge 继续消费请求的修复继续保留。新增 `$PREFIX/local/perf/terminal.status` 作为轻量排障状态文件，便于 Agent 判断合帧和 bridge 工作状态。

2.2.1 的浏览器协作能力继续保留：`auth-open` 默认只打开 App 内安全登录任务卡，不再自动跳出到 Custom Tabs；用户点击“打开/重开”或 Agent 显式调用 `auth-reopen` / `auth-open --open-now` 时才打开系统浏览器。2.2.0 新增的调用式 Custom Tabs 安全登录任务卡，`auth-open/auth-wait/auth-status/auth-done/auth-cancel/auth-reopen` 会把用户完成、取消、折叠、重开等动作结构化回传给 Agent；官方 Codex 登录可走 `codex 官方登录` / 启动前设备码向导，默认使用 `codex login --device-auth`，在安全登录任务卡中展示链接/验证码，用户点击“打开/重开”进入 Custom Tabs 完成授权后再用 `codex login status` 验证。

内置 WebView 继续作为 Agent Browser，保留后台打开、DOM 读取、点击、输入、JS、截图、多标签、Cookie/WebStorage 持久化和 userscript；遇到验证码/风控/外部 scheme 时会进入明确的用户协作状态，而不是让 Agent 猜。

已经安装 2.0.x、2.1.x、2.2.x、2.3.x、2.4.0、2.4.1、2.4.2、2.4.3 或 2.4.4 的用户，直接从 Releases 下载并覆盖安装 2.4.5 APK，然后打开 App。首次启动会自动完成二进制、launcher、脚本、配置档 V2、模型目录和 SQLite 运行世代升级；之后默认进入 shell，输入 `codex` 再启动。无需再执行任何 Codex 更新或修复命令。

升级只使用 APK 内置载荷完成核心迁移。完成后普通启动仍不会远程更新脚本、自动请求第三方 `/models` 或覆盖用户手写配置。`codex 更新` 只用于用户没有更新 APK、明确只想热更新脚本的场景。

## 2.0 新功能

- 2.4.5 体验：默认 shell、设置可恢复自动进 Codex、过滤 proot 噪声、workspace 减黄字、日常升级静默秒退。
- 2.4.4 热修：恢复文件托盘发送「附加说明」对话框。
- 2.4.3 热修：清除 musl 上不可用的 `code_mode_only`，恢复 `gpt-5.6-*` 工具调用；升级时规范化模型目录。
- 2.4.2 完整升级：APK 覆盖安装自动升级固定二进制、launcher、脚本、配置和模型目录；失败回滚并阻止启动；`/model`、推理强度、`CODEX_HOME`、SQLx 和多站点会话隔离进入真实 PTY/升级矩阵门禁。
- 2.4.1 热修：配置模式失败/返回不再启动 Codex；配置、会话和 SQLite 按 profile/build 隔离；目录层隐藏 `codex-auto-*`，让原生 `/model` 直达完整模型页；推理等级绑定 `rust-v0.144.1` 目录。
- 2.4.0 重构：事务型配置档 V2、稳定 ID CRUD、V1 无损迁移/回滚、动态模型能力、真实上下文与压缩策略。
- 2.3.11 修复：文件托盘/浏览器/会话折叠桥接请求先在非监听临时文件完成，再发布到队列与 legacy request，避免 App 清理队列时触发 shell 端 `mv ... No such file or directory` 竞态。
- 2.3.10 修复：文件托盘缓存生命周期闭环，重启后恢复有效临时文件并清理孤儿缓存，清空/单删/Agent clear/自动淘汰都会同步删除 App 本地副本。
- 2.3.9 修复：文件托盘文本/文件点击“发送”后延迟触发真实 Enter，避免短引用只停在 Codex 输入框而不提交。
- 2.3.8 修复：`codex-context report` / `codex 上下文监测` 在 Android 上使用系统用户时区显示压缩触发时间。
- 2.3.7 新增：`codex-context` 基于 Codex hooks 记录本地/远程压缩来源、本会话压缩次数，并提供 `codex 上下文监测` 用户报告入口。
- 2.3.6 修复：内置浏览器重复打开当前根路径 URL 时，会把 `https://example.com` 与 `https://example.com/` 视为同一次加载，不再误报 `Page load timed out`。
- 2.3.5 修复：第三方 OpenAI-compatible 配置生成 `name = "OpenAI"`，内部 provider id 仍保持 `custom`，旧 `name = "custom"` 可安全规范化且不覆盖用户手写名称。
- 2.3.4 修复：协作浏览器显式动作结果不再被后续 snapshot 覆盖，`codex-browser result <request_id>` 会保留 `action=navigate` 等真实动作。
- 2.3.3 修复：`codex-browser open` 页面主框架完成即可返回，不再被 userscript 回调超时误判失败。
- 2.3.3 修复：`codex-panel/codex-preview/codex-browser events` 按文件托盘/浏览器来源过滤，避免 Agent 状态互串。
- 2.3.3 修复：`codex-dev-transfer export` 默认安全导出避开 `.codex/.tmp` 临时插件缓存，减少迁移包导出失败。
- 2.3.2 加固：正式 Release 必须使用 GitHub Secrets/离线签名输入，仓库 keystore/testkey fallback 被禁用并由 CI 校验。
- 2.3.2 加固：`codex-dev-transfer` 默认排除 auth、Cookie、WebView/db/no_backup/browser 等登录态；导入校验 tar 路径、链接和设备节点。
- 2.3.2 稳定性：普通启动不覆盖用户配置，rootfs 安装和 session 临时目录清理增加锁、ready marker 和原子切换。
- 2.3.1 新增：`codex-doctor`、`codex-clean`、`codex-ops`，支持只读诊断、可回滚清理、任务日志和断线续连提示。
- 2.3.1 加固：files/browser/session/perf 状态补齐 `schema_version`、`timestamp_ms`、`needs_user`、`user_action` 等统一字段，浏览器日志只写脱敏摘要。
- 2.3.1 优化：终端 perf 状态增加平均/最大帧耗时、慢帧、输入事件和近期合帧计数，便于定位卡顿。
- 2.3.0 稳定化：新增 2.3 回归清单和已安装真机 smoke，覆盖安装状态、RTK/context、文件托盘、会话折叠、浏览器后台截图/JS/Auth 和终端 perf 状态。
- 2.3.0 修复：重复 `codex-browser open <当前已加载 URL>` 不再等待新的页面回调直到超时，而是直接返回当前页面，避免稳定化门禁和日常脚本被误判失败。
- 2.2.9 修复：2.2.8 真机复测仍失败的后台/折叠 WebView 截图空图，capture host 改为挂在 App 内容背后，并增加 `enableSlowWholeDocumentDraw`、等待帧和 WebView `onDraw` 与 DOM 文本兜底。
- 2.2.8 尝试修复：后台/折叠 WebView 截图灰白空图，使用透明 capture host、软件层绘制和 `capturePicture` 兜底；部分真机仍为空图，已由 2.2.9 继续修复。
- 2.2.7 修复：`codex-browser js` 裸表达式返回值、Auth 取消状态残留和 RTK/context 系统托管 hook 状态显示；2.2.7 的后台截图在部分真机上仍可能为空图，2.2.8 仍未完全修复，已由 2.2.9 继续修复。
- 2.2.6 修复：bridge 请求队列和 request_id 幂等，避免浏览器请求双执行、文件托盘/session fold/agent panel 快速连续请求丢失。
- 2.2.6 修复：协作浏览器导航 token、状态落盘、外部链接/下载确认和敏感字段脱敏，减少后台浏览和用户协作状态错乱。
- 2.2.6 加固：DocumentsProvider 路径边界、备份排除、FileProvider 分享范围、Release 签名和 GitHub Release 资产发布门禁。
- 2.2.6/2.3.1 加固：release 构建不再借用 debug signingConfig；2.3.1 起正式签名只允许来自 GitHub Secrets/离线签名输入，仓库 keystore fallback 被禁用。
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
- 第三方配置：内部 provider id 保持 `custom`，写入的 provider 名称为 `OpenAI`，`base_url` 可指向兼容 OpenAI Responses API 的第三方服务。
- 文件协作：支持图片、视频、文本预览、用户选文件、长按分享；文件卡片点“发送”会立即提交到当前会话。
- 浏览器协作：支持内置 WebView、Custom Tabs/系统浏览器接管、多标签和页面自动化桥接。
- 本地维护：普通启动不改配置；脚本更新和模型目录刷新都由用户显式命令触发。

它不是 OpenAI 官方发布渠道，也不是一个泛用 Linux 发行版 App；它的目标很明确：让 Android 用户更稳地进入 Codex TUI。

## 当前版本

| 项目 | 当前值 |
| --- | --- |
| Android App | `2.4.5` |
| 包名 | `com.gzy3894.codexfortui` |
| Debug/Test 包名 | `com.gzy3894.codexfortui.test` |
| Codex CLI | `0.144.1` 中文版 |
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

安装或 APK 版本迁移完成后，重新打开 App 会直接进入本地 `codex`，不会在日常启动中自动联网更新脚本、刷新 `/models` 或覆盖 `~/.codex/config.toml`。也可以在终端里手动运行：

```sh
codex
```

如果没有更新 APK，只想显式热更新安装/配置脚本，可以输入：

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

`codex 配置模式` 会打开事务型配置档 V2，围绕增、删、改、查和切换工作：新建配置、选择配置、编辑配置、查看配置、删除配置、刷新模型目录、上下文/压缩策略和修复全权限授权。配置档使用稳定 ID；编辑不会变成同名新建，取消确认不会写入。第三方配置会保存 `config.toml`、`auth.json` 和 `model_catalog_json`；切换或退出前若检测到手改配置、登录态或目录变化，会提示同步当前配置、另存或暂不保存。通用配置、注释和未知 TOML 字段会保留；全权限模式会同时写入 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`。

第三方模型目录刷新也可以手动执行。Provider `/models` 只决定可用模型 ID，真实推理等级、上下文窗口和工具能力从随包 OpenAI Codex 官方目录精确合并；未知模型使用保守能力，可通过映射文件补充。所有 `codex-auto-*` 辅助模型保留在目录中但标记为隐藏，使 `/model` 首层直接进入完整普通模型页；已有 profile 会在 APK 迁移或本地物化时应用同一策略。刷新会保留当前 `model` 和 `model_reasoning_effort`，如果当前选择已不再受支持会回落到该模型的上游默认值并报告：

```sh
codex-local refresh-models
```

配置档和压缩策略也可以直接用命令管理：

```sh
codex-local profile-list
codex-local profile-show <名称或ID>
codex-local profile-use <名称或ID>
codex-local profile-rename <名称或ID> <新名称>
codex-local profile-delete <名称或ID>
codex-local profile-sync <名称或ID>
codex-local compact-policy show
codex-local compact-policy follow-model
codex-local compact-policy fixed 220000
codex-local config-status
codex-local rollback-v1
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

用户也可以在托盘里点“添加”，用 Android 系统文件管理器选择文件。托盘第一格是常驻文本框，发送后会保存为文本引用并清空输入框；文件卡片点“发送”会立即提交到当前会话。终端提示只会展示短文件编号；需要在 shell 中解析真实路径时使用：

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
codex-context report
codex-context events
codex-context verify
codex-context disable
codex 上下文监测
```

`codex-context status` 是给 Agent 读的机器信号：`PreCompact auto` 出现时会标记自动压缩即将发生，便于 Agent 做保存、摘要或交接准备。`codex-context report` / `codex 上下文监测` 是给用户看的简报，只显示“几点几分触发了一次本地/远程压缩，当前会话已压缩 X 次”。脚本只写入 `~/.codex/context-state/` 和 App 的会话事件流，不会阻止 Codex 自动压缩，也不会读取、扫描或改写 session/transcript 文件。

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
1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61  codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz
0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767  codex-0.144.1-zh-aarch64-unknown-linux-musl
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

脚本生成的第三方配置会保留内部引用 `model_provider = "custom"`，但 provider 显示/协议名写为 `name = "OpenAI"`：

```toml
[model_providers.custom]
name = "OpenAI"
base_url = "https://api.example.com/v1"
wire_api = "responses"
requires_openai_auth = false
```

**Codex 结束时出现 hook 相关错误？**

2.0.8 起配置模式默认写入：

```toml
[features]
hooks = true
```

如果你迁移过旧配置，运行 `codex` 并在启动前选择 `1. 快捷授权并启动 Codex`。脚本会把 RTK/context 写入系统级 `requirements.toml`，只管理 Codex for TUI 托管 hook；必要时清理 `~/.codex/config.toml` 里的旧版兼容 hook 块，不遍历或改写 session/transcript 文件。`codex-rtk disable` 或 `codex-context disable` 只用于移除旧版手动写入的兼容 hook 配置。

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
