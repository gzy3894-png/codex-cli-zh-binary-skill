# Codex for TUI 终端本体地图

> 状态：基于仓库 `android-app/` 与已装 2.5.23 实机结构阅读整理（2026-07-13）。  
> 用途：后续长文本强制投递、会话折叠稳定化、通知/弹窗/悬浮窗等原生能力的开发真源入口。  
> 不替代源码；改行为前仍以对应 `.kt` / assets 为准。

## 1. 一句话结论

**终端本体是「Termux PTY 渲染 + App 文件桥 + 可选 Agent 工具」三层拼装。**

- **PTY 路径只负责显示字节流**，不理解 Codex 消息语义。
- **文件托盘 / 浏览器 / 会话折叠** 全靠 `$PREFIX/local/<bridge>/` 上的 request/queue/status/events。
- **没有任何层会自动把 assistant 长输出吸进托盘或折叠时间线**；不调 CLI / 不写 bridge，UI 侧就“像没功能”。

这解释了：

1. 会话折叠“一直不稳定触发”——它不是自动折叠，而是 **被动 bridge**。
2. 仅靠提示词 / 工具路由做长文本强制——和折叠同一失败模式，**不能当产品保证**。

---

## 2. 模块边界

```
┌─────────────────────────────────────────────────────────────┐
│ App 进程 (com.gzy3894.codexfortui)                          │
│  MainActivity ── Compose UI (TerminalScreen / panes)        │
│       │                                                      │
│       ├─ FileObserver + poll ── local/media-preview         │
│       ├─ FileObserver + poll ── local/browser               │
│       ├─ FileObserver + poll ── local/session-fold          │
│       ├─ agent-panel status/events (聚合)                   │
│       └─ SessionService (FGS) ── TerminalSession map         │
│                │                                             │
│                └─ MkSession → /system/bin/sh + init-host     │
│                              → proot Alpine → codex/shell    │
└─────────────────────────────────────────────────────────────┘
          ▲ write request/queue/*.req
          │
┌─────────┴──────────┐
│ Alpine / Agent CLI │  codex-preview / panel / session / browser
└────────────────────┘
```

| 层 | 位置 | 职责 | 不负责 |
|---|---|---|---|
| UI / bridge 宿主 | `MainActivity.kt` (~3509 行) | 监听 bridge、更新 ViewModel、写 status/events/result | 解析 PTY 里的 agent 文本 |
| 会话生命周期 | `SessionService.kt` | 多窗口 PTY、前台通知、优雅退出 | 对话内容、托盘内容 |
| 会话元数据 | `session/SessionIsolation*.kt` | 标签名、agent 绑定、resume UUID、launcher/worker | 消息折叠、长输出 |
| PTY 客户端 | `TerminalBackEnd.kt` | Termux `TerminalSessionClient`：渲染合并、输入行缓冲、命名钩子 | 输出语义、托盘 |
| 会话创建 | `MkSession.kt` | env、managed scripts 同步、启动 `init-host` | bridge 协议 |
| 托盘 UI | `MediaPreviewPane.kt` | 图/文/视频预览、多选发送 | 生产内容 |
| 折叠 UI | `SessionFoldPane.kt` | 时间线展示 | 生产 run/item |
| 浏览器 | `TerminalBrowserSession.kt` + `BrowserPanelPane.kt` | Custom Tabs / 信号 | 读页面密码 Cookie |
| Shell bridge | `assets/codex-{preview,panel,session,browser,...}` | 写 queue 请求 | App 侧状态机 |
| 模拟器库 | JitPack `termux-app` terminal-view/emulator **v0.118.3** | VT 渲染与 PTY | 业务 |

Gradle 入口：`android-app/settings.gradle.kts`  
依赖：`core/main/build.gradle.kts` → `com.github.termux.termux-app:terminal-{view,emulator}:v0.118.3`

---

## 3. 进程与权限（原生扩展锚点）

`android-app/app/src/main/AndroidManifest.xml`：

| 组件 | 说明 |
|---|---|
| `MainActivity` | 唯一 LAUNCHER；`adjustResize` |
| `SessionService` | 非导出 FGS，`foregroundServiceType=specialUse` |
| `FileProvider` | 分享托盘文件（`file_paths.xml` → `media-preview-share/`） |
| 权限 | `INTERNET`、`POST_NOTIFICATIONS`、外存、`FOREGROUND_SERVICE(_SPECIAL_USE)` |

**已有通知能力**：`SessionService` 只做“N sessions running + EXIT”，**不是**业务消息推送通道。  
后续推送/弹窗/悬浮窗应 **新建 channel + 独立入口**，不要塞进 session 保活通知的语义里。

当前 **没有**：

- `SYSTEM_ALERT_WINDOW` / 悬浮窗
- 通用业务 `NotificationChannel`（除 session 保活）
- BroadcastReceiver / 深链 Activity 扩展点（仅 MAIN）

---

## 4. 目录真源（bridge 文件系统）

App 侧 `localDir()` ≈ `$PREFIX/local`，实机常见：

```text
/data/user/0/com.gzy3894.codexfortui/local/
  bin/                 # codex-preview 等 managed wrappers
  media-preview/       # 文件托盘
    request | queue/*.req | status | result | events?
    files/ | refs/
  browser/
  session-fold/        # 会话折叠
    request | queue/ | status | result | events | entries/
  agent-panel/         # 聚合 status/events
  session-bind/ | perf/ | ops/ | proot-tmp/
```

Alpine 内 `PREFIX` / `PKG` 由 `MkSession` 注入，CLI 用 `find_prefix()` 定位同一棵树。

### 4.1 统一请求发布模式（2.3.11）

所有 bridge CLI 共用思路：

1. 在 bridge 根写完整 `.<id>.req.tmp`
2. 复制到 `queue/.<id>.req.tmp` → `mv` 为 `queue/<id>.req`
3. 再写 legacy `request`（兼容旧轮询）

App：`FileObserver`（request + queue）+ 协程 poll；`request_id` 去重缓存，避免 clear 竞态半文件。

### 4.2 状态字段（2.3.1+）

status/events 常见键：

- `schema_version=2.3.1`
- `timestamp_ms` / `stamp`
- `source` / `mode`（files|browser|session|…）
- `state` / `reason` / `request_id` / `item_id`
- `needs_user` / `user_action`
- 面板：`visible` / `collapsed` / `shown`
- session-fold：`run_id` / `active_run` / `runs` / `items` / `timeline_collapsed`

---

## 5. 文件托盘（media-preview）

### 5.1 CLI

`assets/codex-preview`：

```text
codex-preview [--present|--background] /path
codex-preview [--present|--background] text --stdin [--name NAME]
codex-preview path|present|collapse|toggle|select|remove|clear|status|events|...
```

- `kind`：扩展名推断，或显式 text stdin → `kind=text`
- `present=0`：只入列不抢焦点；默认 present 展开托盘

`codex-panel` 是 files/browser 控制面（present/collapse/clear/select…）。

### 5.2 App 处理

`MainActivity.handleMediaPreviewRequestContent`：

| action | 行为 |
|---|---|
| `show`（默认，带 path） | 读文件 → `TerminalMediaPreview` → 列表；`present!=0` 则展开 |
| `present/collapse/toggle/done/cancel` | 只改展开态 |
| `select/remove` | 按 `item_id` |
| `clear` | 清 VM + files/refs/queue |

**副作用**：成功 show 时若存在 `activeSessionFoldRunId`，会 `appendActiveSessionFoldItem`（TEXT/FILE）。  
**若没有先 `codex-session start`，折叠时间线不会出现条目。**

### 5.3 UI

`MediaPreviewPane.kt`：预览、多选、顶部发送、短名「图片N/文本N」、附加说明。  
发送走 `sendPreviewsToAi` → 解析 live target（`SessionTargetResolver` / `SessionService`）→ 写入 worker PTY，避免落到 launcher。

---

## 6. 会话折叠（session-fold）— 为何“从不自动触发”

### 6.1 设计

| 组件 | 作用 |
|---|---|
| CLI `codex-session` | start/add/done/fail/expand/collapse/timeline/clear |
| `handleSessionFoldRequestContent` | 解析 action → `TerminalViewModel.sessionFoldRuns` |
| `SessionFoldPane` / `TerminalScreen` | 画时间线 |

Item kind：`thinking | tool | text | file | browser | final`。

### 6.2 关键事实（源码级）

在 `android-app` + `android-arm64-musl` 内：

- **没有** PTY 输出嗅探去 `start/add` fold
- **没有** Codex 二进制内置调用 `codex-session`
- `codex-session-defaults` 的 hook **只**处理 model/defaults 类事件，**不**驱动折叠
- `appendActiveSessionFoldItem` **要求**已有 `activeSessionFoldRunId`；否则直接 return

因此折叠 **100% 依赖** 外部显式：

```sh
codex-session start --run R "标题"
codex-session add text --run R --stdin ...
codex-session done R "摘要"
```

实机 `session-fold/status` 可见 installed-smoke 写入的 run；日常对话若 agent 不调 CLI，时间线保持空/旧状态——这不是 UI bug，是 **协议未接入消息生命周期**。

### 6.3 与“提示词强制”的同构失败

| 机制 | 依赖 agent 自觉 | 失败时用户感知 |
|---|---|---|
| session-fold | 必须调 `codex-session` | “折叠从不触发” |
| 长文进托盘（仅 skill） | 必须调 `codex-preview` | 终端被刷屏 |
| 工具路由 deliver | 必须选工具 | 同上 |

**产品级强制必须在「消息落屏之前」有非可选执行点**，不能停在 outer skill。

---

## 7. PTY / 渲染路径（强制输出的唯一“底层”候选）

### 7.1 创建

`SessionService.createSession` → `MkSession.createSession`：

- shell：`/system/bin/sh`，Alpine 模式 args：`init-host` 绝对路径
- env：`PREFIX` `PKG` `CODEX_HOME` `CODEX_FOR_TUI_*` `PROOT_*` `PATH` 含 `local/bin`
- managed scripts：按 versionCode stamp 同步 assets → `local/bin`

### 7.2 输出

`TerminalBackEnd.onTextChanged`：

1. 确认当前 session
2. 合并刷新（用户输入 0ms / 文本 16ms）
3. `terminal.onScreenUpdated()` → Termux 绘制

**没有**对 `changedSession` 屏幕文本做业务解析的钩子。  
`onTitleChanged` 为空实现。

### 7.3 输入

- 行缓冲 + Enter → `AgentWindowCoordinator.route`（仅 **LAUNCHER** 识别 `codex/claude/...` 开 worker）
- 否则 `SessionIsolationHooks.onUserSubmittedLine`（命名等）
- 虚拟键 / 快捷键：`VirtualKeys*` `KeyShortcutHandler`

### 7.4 含义

若要做 **C 类“强制长输出改道”**，候选插入点只有：

| ID | 插入点 | 可行性 | 风险 |
|---|---|---|---|
| C1 | `TerminalBackEnd.onTextChanged` 读 emulator buffer | 不改 Termux AAR | 高：ANSI/分页/流式/spinner 误伤 |
| C2 | fork `terminal-emulator` 在 write 路径挂钩 | 可控但维护重 | 高：跟 v0.118.3 |
| C3 | Alpine PTY wrapper（`script`/伪 tty 过滤） | 可开关 | 中高：与 proot/codex TUI 交互 |
| C4 | Codex 二进制/patch 在 assistant final 落盘 | 语义最准 | 极高：绑定 `0.144.1-zh.1` |
| C5 | App 侧 **结构化 bridge 新通道**（agent runtime 必写） | 中 | 中：仍需 runtime 接入，但比提示词硬 |

**推荐产品方向**：不要把 C1 当第一刀；优先 **运行时必写 bridge（C5）+ test 通道验证**，PTY 嗅探仅作 test 开关兜底。

---

## 8. 会话隔离 vs 会话折叠（易混）

| | SessionIsolation | session-fold |
|---|---|---|
| 问题 | 哪个终端窗口、叫什么、resume 谁 | 一次 agent run 的步骤时间线 |
| 存储 | `filesDir/session-isolation/registry.json` 等 | `local/session-fold` + 内存 VM |
| 触发 | 开窗/输入/绑定 | **仅** bridge CLI |
| 关闭窗口 | 不删 codex 对话 | 不自动 clear fold |

---

## 9. 源码索引入口（按改动类型）

| 要改什么 | 先读 |
|---|---|
| 托盘协议 / 长文本展示 | `assets/codex-preview`，`MainActivity` media 段，`MediaPreviewPane.kt` |
| 折叠协议 | `assets/codex-session`，`handleSessionFoldRequestContent`，`SessionFoldPane.kt`，`TerminalViewModel` fold API |
| 浏览器 | `assets/codex-browser`，`TerminalBrowserSession.kt`，MainActivity browser poll |
| 多窗口 / 通知保活 | `SessionService.kt`，`MkSession.kt`，`WorkerCommandLauncher.kt` |
| 启动与 env | `MkSession.kt`，`assets/init-host.sh`，`init.sh` |
| 输入路由 agent | `AgentWindowCoordinator.kt`，`AgentCatalog.kt`，`TerminalBackEnd` flush |
| 性能 | `TerminalRenderPerformanceMetrics`，`local/perf` |
| 权限 / 组件 | `app/.../AndroidManifest.xml` |

`MainActivity` 函数索引（bridge 相关）：`start*Bridge` / `poll*Request` / `handle*RequestContent` / `write*Status|Event|Result` / `appendActiveSessionFoldItem`。

---

## 10. 对后续原生能力的约束

1. **Bridge 模式可复用**：推送/弹窗可先 `local/<name>/request` + MainActivity 观察者，与 preview 同构，便于 Alpine agent 调用。  
2. **UI 能力要在 Activity/Service**：悬浮窗、系统通知必须 App 进程；CLI 只能发意图。  
3. **FGS 通知勿混用**：session 保活 channel 保持 low importance；业务通知另开 channel + `POST_NOTIFICATIONS` 运行时权限流。  
4. **PTY 不是 IPC**：不要假设从屏幕 OCR/缓冲能稳定还原 markdown 结构。  
5. **test 通道**：高风险改动必须 `versionName` test / 独立 feature flag，且 installed smoke 覆盖 bridge 全链路。

---

## 11. 相关文档

- 强制长文本与折叠稳定化方案：[`long-output-and-fold-strategy.md`](./long-output-and-fold-strategy.md)
- Bridge 协议速查：[`bridge-protocol.md`](./bridge-protocol.md)
- 历史：`docs/worklogs/2.3.1/W-B-bridge.md`，`docs/codex-for-tui-2.3.0-regression.md`
