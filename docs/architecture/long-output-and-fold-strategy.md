# 长文本强制投递 + 会话折叠稳定化方案

> 依赖：[`terminal-core-map.md`](./terminal-core-map.md)、[`bridge-protocol.md`](./bridge-protocol.md)  
> 原则：**test 通道优先**；不把提示词/外挂 skill 当产品保证；高风险改动可开关、可回滚。

## 0. 问题定性

| 现象 | 根因 |
|---|---|
| 会话折叠很少“自己出现” | 仅 `codex-session` bridge；PTY/Codex 无自动埋点 |
| 长总结刷屏 | assistant 最终文本直接进 PTY；托盘需显式 `codex-preview` |
| 外挂式方案没意义 | 与折叠同构：依赖模型自觉 → 无法强制 |

**结论：同意必须做“非可选执行点”（你称的 C）。**  
但 C 应落在 **消息生命周期 / runtime 接入**，而不是第一天就盲改 Termux 渲染或固定 Codex 二进制。

---

## 1. 目标（产品语义）

### 1.1 长文本强制

当输出满足策略（见 §3）时：

1. 完整内容写入 **工作区文件**（可 resume/可分享真源）  
2. 经 **media-preview** 入托盘（`kind=text`）  
3. 终端 **只保留短摘要**（结论 + `文本N` + `codex-preview path <id>`）  
4. 可选：挂到当前 session-fold run 的 `text/final` item  

### 1.2 会话折叠稳定

一次 agent 任务（或一次 turn）必须有：

```text
start → (thinking|tool|text|file|browser)* → done|fail
```

由 **运行时** 写 bridge，而不是靠模型记得调用。

### 1.3 非目标（第一期）

- 完美还原 Codex TUI 内部 spinner/差分动画  
- 拦截所有工具 stdout（易误伤）  
- 替换 Termux 依赖主版本  

---

## 2. 架构：强制点放哪

```text
                    ┌──────────────────────┐
   推荐主路径        │ Runtime Emitter (RE) │  结构化事件
                    │ turn/start/delta/end │
                    └──────────┬───────────┘
                               │ 写 local/* bridge
                               ▼
                    ┌──────────────────────┐
                    │ MainActivity bridges │  已存在
                    │ preview + session-fold│
                    └──────────────────────┘

   兜底 test-only   ┌──────────────────────┐
                    │ PTY Tap (可选)        │  onTextChanged / wrapper
                    │ 启发式超长 → 吸托盘   │
                    └──────────────────────┘
```

| 路径 | 强制？ | 语义准确？ | 风险 | 用途 |
|---|---|---|---|---|
| **RE：Runtime Emitter** | 是（接入后） | 高 | 中 | **主路径** |
| Skill / 提示词 | 否 | 中 | 低 | 仅开发期辅助，不写进验收 |
| PTY Tap | 半强制 | 低 | 高 | test 开关兜底，默认 off |
| Patch Codex 二进制 | 是 | 高 | 极高 | 仅当 RE 无法挂钩时 |

### 2.1 Runtime Emitter 候选挂钩（按优先级）

1. **Codex hooks 扩展**  
   - 已有 `codex-session-defaults hook`（仅 settings）  
   - 扩展独立 adapter：`codex-tui-turn-bridge` 订阅 turn 生命周期（若 upstream hook 面足够）  
2. **App 托管 wrapper**  
   - worker 启动不直接 `codex`，而 `codex-tui-agent-wrap` → 仍 exec 原二进制，但并行消费 **机器可读事件流**（若有 jsonl/notify）  
3. **会话 jsonl 尾随（只读）**  
   - 读 `CODEX_HOME/sessions/**.jsonl` 新行 → 映射为 fold/preview  
   - 不改 PTY；延迟略高；语义优于屏幕刮擦  
4. **PTY Tap**  
   - 仅 test；阈值+静默期启发式  

**禁止**把“AGENTS.md 写一句必须 preview”当作强制完成。

---

## 3. 策略配置（建议默认）

`local/ops/long-output.policy` 或 Settings（后续）：

| 键 | 建议默认 | 说明 |
|---|---|---|
| `enabled` | test 包 true / release 先 false 或 shadow | 总开关 |
| `mode` | `bridge` \| `bridge+pty_tap` | |
| `min_lines` | 40 | |
| `min_chars` | 1500 | |
| `types` | summary,plan,matrix,final | 有结构化 kind 时 |
| `terminal_summary_lines` | 8 | |
| `present` | `1` test / 可配 `0` | 是否自动展开托盘 |
| `fold` | `1` | 同步 fold |
| `workspace_dir` | `$CODEX_FOR_TUI_WORKSPACE/deliveries` | 真源目录 |

Shadow 模式：执行投递但 **仍保留全文在 PTY**（只加托盘）——用于对比，不作为最终 UX。

---

## 4. 分阶段交付（必须 test 通道）

### Phase 0 — 文档与探针（本阶段产出）

- [x] 本体地图 / 协议 / 本方案  
- [x] 实机探针：统计自然对话中 `codex-session` / `codex-preview` 调用率（证明外挂失败）— 见 §10  
- [ ] 明确 test 包标识：`versionName` 后缀 `-test` 或独立 `applicationId` 后缀（二选一，发布时定）

### Phase 1 — Fold 自动埋点 MVP（先修“从不触发”）

**目标**：任意一次 Codex turn 至少出现 start/done（或 jsonl 推导的等价物）。

实现顺序：

1. 选挂钩：**优先 sessions jsonl tail**（不改二进制、不改 PTY）  
2. App 或 Alpine daemon：`codex-tui-session-tail`  
   - 监听 active runtime 的 jsonl  
   - 映射事件 → `codex-session start/add/done`  
3. feature flag；失败 best-effort 不阻断 codex  
4. smoke：跑一轮对话 → `session-fold/status` runs≥1 items≥1  

**验收**：不用模型“记得调用”，时间线稳定出现。

### Phase 2 — 长文本强制投递 MVP

在 Phase 1 事件上识别 **final/assistant 长消息**：

1. 落盘 `deliveries/<ts>-<title>.md`  
2. `codex-preview --present|--background`  
3. **抑制重复全文进 PTY**（难点，见 §5）  
4. 终端摘要行由 RE 写入（短文本 write 到 PTY 或仅 status 提示）

### Phase 3 — 原生通知 / 弹窗 / 悬浮窗

复用 bridge 模板新增例如 `local/notify/`：

| 能力 | Android API | 注意 |
|---|---|---|
| 通知栏 | `NotificationChannel` + `POST_NOTIFICATIONS` | 与 FGS 保活 channel 分离 |
| 应用内弹窗 | Compose Dialog / Activity overlay | 不需新权限 |
| 悬浮窗 | `SYSTEM_ALERT_WINDOW` | 引导设置页；默认 off |
| 推送 | 后置；先本地 notify bridge | 避免过早绑定厂商推送 |

协议示例：

```text
action=notify
title=...
body=...
priority=default|high
deep_link=codexfortui://session/<id>
```

MainActivity/Service 消费；agent CLI：`codex-notify ...`。

### Phase 4 — PTY Tap 兜底（可选，默认 off）

仅当 Phase 1–2 挂钩覆盖不足：

- 在 `TerminalBackEnd.onTextChanged` 采样 emulator transcript 增量  
- 静默 T ms 且增量 > 阈值 → 吸到文件 + preview  
- **永不**默认在 release 开启，直到误伤率可测  

---

## 5. “终端不再刷全文”的技术难点

托盘能做 ≠ 终端自动变短。可选策略：

| 策略 | 说明 | 推荐 |
|---|---|---|
| S1 源头不打印全文 | runtime 把 final 改成摘要+path | **最干净** |
| S2 打印后清除 | 向 PTY 发清屏/回卷 | 易花屏，差 |
| S3 双通道 | UI 旁路显示摘要卡片，PTY 仍有全文 | 过渡 |
| S4 用户设置“紧凑模式” | 明确开关 | 与 S1 组合 |

**强制体验的完成标准 = S1**，不是“多写一个文件但终端仍全文”。

S1 依赖 RE 能在 **final 提交前**改写或分流；jsonl-only 尾随偏 S3（先有全文再补托盘）。  
立项时要在 test 包上对比：jsonl 延迟 vs hook 同步。

---

## 6. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 误吸工具日志/进度条 | kind 白名单；仅 final；冷却时间 |
| 双份内容更吵 | 完成标准强制 S1 或 shadow 仅 test |
| jsonl 格式漂移 | 适配器版本化；解析失败打 perf/ops 日志 |
| 性能 | tail 增量；主线程只收事件 |
| 隐私 | deliveries 仅 app 私有；通知不带密钥 |
| 与 0.144.1-zh.1 绑定 | 避免改二进制；挂钩放 App/adapter |

回滚：flag off → 退回纯 PTY；bridge 文件可留。

---

## 7. 测试矩阵（test 包门禁）

| 用例 | 期望 |
|---|---|
| 短回复 < 阈值 | 不进托盘、不扰民 |
| 长 final | 文件 + preview status kind=text + 终端摘要策略符合 mode |
| 折叠 | 单 turn 有 start…done；杀进程再进不要求持久（P1 可内存） |
| 无 agent 纯 shell | 零 fold、零误 preview |
| preview clear | 无 queue 半文件报错（回归 2.3.11） |
| flag off | 与 2.5.23 行为一致 |
| 通知 bridge | 本地通知出现；点回正确 session |

本地：static-guards 扩展；**禁止**本地 Gradle 正式包（沿用 GHA）；test APK 同样走 CI。

---

## 8. 建议的工程切片（可直接开 issue）

1. **T-DOC** 本文档（完成）  
2. **T-PROBE** 调用率探针 + 失败基线数据  
3. **T-FOLD-JSONL** session-fold 自动埋点 MVP + flag  
4. **T-DELIVER** deliveries + preview 强制（先 S3 shadow）  
5. **T-S1** 终端摘要分流（真正“不刷屏”）  
6. **T-NOTIFY** 本地通知 bridge  
7. **T-PTY-TAP** test-only 兜底  

---

## 9. 对你原话的直接回答

| 问题 | 回答 |
|---|---|
| 不做 C 有没有意义？ | **产品强制层面没有**；A/B 只能作开发辅助 |
| 折叠从未稳定触发是否证明外挂失败？ | **是**；源码证明无自动路径 |
| 高风险是否走 test？ | **必须**；flag + test 包 + 可回滚 |
| 先啃本体是否可行？ | **可行且必要**；地图/协议/方案已落盘 |
| 是否一上来改 Termux/PTY？ | **不建议**；先 RE（jsonl/hook），PTY 作 test 兜底 |

用户已确认方案 A。**T-PROBE 完成**（§10）；下一步 **T-FOLD-JSONL**（flag 默认 off），不碰 release 2.5.23 默认行为。

---

## 10. T-PROBE 基线（2026-07-13）

机器报告：`/root/agent-shared/workflows/logs/2026-07-13-long-output-fold-force-t-probe-report.json`

| 项 | 结果 |
|---|---|
| session-fold | 691 events；agent lifecycle 85；**started run 几乎全是 installed-smoke/selftest** |
| status | `reason=installed_smoke`，`active_run` 空 |
| media-preview | **无 kind=text 残留**（仅 1 个 image ref） |
| 自然 CLI | shell history 无 `codex-session`；rollout 命中多为代码/文档/图片路径 |
| 长消息 | 抽样 664 条 assistant；p50=147 字；≥1500 约 4.5% |

**结论**：外挂 CLI 不能当产品强制点。Runtime Emitter 主路径成立。

### 推荐 jsonl 映射（T-FOLD MVP）

```text
task_started  → codex-session start --run <turn_id>
task_complete → codex-session done <turn_id>
turn_aborted  → codex-session fail <turn_id>
```

flag 建议：`local/ops/session-fold-bridge.policy` 或 env `CODEX_TUI_FOLD_BRIDGE=0|1`，**release 默认 0**。

---

## 11. T-FOLD 启用（test）

实现（POC）：`android-arm64-musl/libexec/codex-tui-fold-bridge.py`  
策略样例：`docs/architecture/session-fold-bridge.policy.example`  
设备策略路径：`$PREFIX/local/ops/session-fold-bridge.policy`

| 模式 | enabled | mode | 行为 |
|---|---|---|---|
| release 默认 | 0 | dry-run | 不写 session-fold |
| 观测 | 0 | dry-run | `map-file` 只打印将要执行的 CLI |
| test 强制 | 1 | apply | 调用 `codex-session start/done/fail` |

```sh
# 自测
python3 android-arm64-musl/libexec/codex-tui-fold-bridge.py self-test
python3 android-arm64-musl/libexec/codex-tui-fold-bridge.py map-file "$CODEX_HOME/sessions/.../rollout-....jsonl"

# 临时开启（测完务必关）
cat > "$PREFIX/local/ops/session-fold-bridge.policy" <<EOF
enabled=1
mode=apply
title_prefix=turn
EOF
# apply 后：
cat > "$PREFIX/local/ops/session-fold-bridge.policy" <<EOF
enabled=0
mode=dry-run
EOF
```

**N3.4（库内包装）✅ 2026-07-13**：`discover-active` / `watch`、CLI asset `codex-tui-fold-bridge`、libexec 进 common/local/bootstrap/apk-upgrade 清单、MkSession managedScripts、`tests/codex-for-tui-fold-bridge-smoke.sh` + static `test_fold_bridge_runtime_emitter`。默认仍 `enabled=0`。

**N3.5（ensure-watch）✅ 2026-07-13**：`ensure-watch`/`stop-watch` + launcher `codex_for_tui_ensure_fold_bridge_watch`；仅 flag on 启 daemon。

**仍缺（装包验收）**：D7 flag on 真机验收、installed-device 专项、与 T-DELIVER 共用 emitter；media-preview **文本复制**源码已修（`MediaPreviewPane.kt`）待 GHA 发版。

受控冒烟（2026-07-13）：合成 `task_started/complete` → status `run_id=fold-bridge-smoke-*` `state=done`；policy 已恢复 off。
