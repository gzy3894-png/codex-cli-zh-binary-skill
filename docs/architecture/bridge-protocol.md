# Bridge 协议速查

> 与 [`terminal-core-map.md`](./terminal-core-map.md) 配套。实现以 assets CLI + `MainActivity` 为准。

## 1. 通用布局

```text
$PREFIX/local/<bridge>/
  request          # legacy 单槽（完整 kv 文本）
  queue/<id>.req   # 有序队列（优先消费）
  status           # App 写，CLI 读
  result           # App 写，单次请求结果
  events           # App 追加，--- 分隔
  # 可选：
  files/ refs/     # media-preview
  entries/         # session-fold 长文本落盘
  screenshots/     # browser
```

发布（CLI）：tmp → queue 原子 mv → legacy request。  
消费（App）：先 `queue/*.req` 排序处理并删除，再处理 legacy `request`（内容去重）。

## 2. media-preview（文件托盘）

### 请求字段（show）

| 键 | 含义 |
|---|---|
| `action` | 默认 `show`；或 present/collapse/toggle/done/cancel/select/remove/clear |
| `path` | 可读文件绝对路径 |
| `kind` | `image` \| `video` \| `text` |
| `name` | 显示名 |
| `stamp` / `request_id` | 去重与 ref |
| `present` | `0` 后台入列；否则展开托盘 |
| `item_id` | select/remove |
| `reason` | 审计 |

### CLI 示例

```sh
codex-preview --present ./plan.md
codex-preview --background text --stdin --name '任务总结.md' <<'EOF'
...
EOF
codex-preview path <FILE_ID>
codex-panel present files agent_review
codex-panel status files
```

### App 结果

- 写入 `status` / `result` / `agent-panel` events
- TEXT：`readTextPreview` 截断预览进 VM
- 若 `activeSessionFoldRunId` 非空：附加 fold item

## 3. session-fold（会话折叠）

### 请求 action

| action | 必填 | 效果 |
|---|---|---|
| `start` | `run_id?` `title?` | 新建/更新 run，`status=running` |
| `add` | `kind` `run_id?` `summary?` `path?` `title?` `item_id?` | 追加 item |
| `done` / `fail` | `run_id` `summary?` | run 结束，默认 collapsed |
| `expand` / `collapse` | `run_id` | run 折叠态 |
| `timeline_collapse` / `expand` / `toggle` | | 整条时间线 |
| `remove` | `run_id` | 删 run |
| `clear` | | 清空 + 删 entries |

### CLI 示例

```sh
codex-session start --run task-1 "实现配置删除"
codex-session add thinking --run task-1 --summary "分析入口"
codex-session add text --run task-1 --stdin --title "方案"
codex-session done task-1 "已完成"
```

### 硬依赖

- **无 start → 无 active run → media 的 appendActiveSessionFoldItem 空操作**
- **无任何代码路径在 assistant 输出时自动 start**

## 4. browser

见 `codex-browser` usage：open/present/collapse/screenshot/click…  
App：`TerminalBrowserSession` + Custom Tabs；结果 JSON 脱敏（auth code/url）。

## 5. agent-panel 聚合

`local/agent-panel/status|events`：files/browser 等 `source=` 分流。  
`codex-panel events files|browser` 按 source/mode 过滤。

## 6. 扩展新 bridge 的最小模板

1. `assets/codex-<name>`：find_prefix + write_queued_request  
2. `MkSession.managedScripts` + init wrappers  
3. `MainActivity`：prime + startBridge + poll + handle + write status/result/events  
4. ViewModel 状态 + Compose pane（如需）  
5. static-guards + installed-device smoke  
6. **不要**只写 skill 文档当作“已接入”

## 7. 反模式

- 只改提示词期望 agent 调 CLI  
- 在 `onTextChanged` 里用正则“猜”完整 markdown 当协议  
- 把业务通知写进 `session_service_channel`  
- 在 bridge 请求里塞密钥/cookie（browser 已做脱敏先例，照做）
