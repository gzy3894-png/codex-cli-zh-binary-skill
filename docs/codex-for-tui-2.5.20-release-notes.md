# Codex for TUI 2.5.20

2.5.20 是 2.5.19 后的**启动性能**热修。2.5.19 已完成配置模式统一、krill `service_tier` 清理与 provider 同步 fast path；本版针对用户反馈「Codex 启动将近半分钟」继续下刀。

## 根因

原生 `/resume` 跨站可见性依赖 Codex++ 风格 dual-sync：

1. 改写共享 rollout 的 `session_meta.model_provider`
2. restamp 各 runtime SQLite `threads.model_provider`

2.5.19 的 `fast=True` marker 在 **sessions 未变化** 时可跳过全量同步。但用户每开一轮新会话都会推进 sessions mtime，marker 失效后旧实现会对 **每一个** `rollout-*.jsonl` 做整文件 `read_text` + 行扫描。本机实测约 93 个文件 / 173MB（最大单文件约 94MB）；热路径整文件扫描约 2.3s，手机存储与冷页上可放大到用户体感的半分钟级。

另外，`session_meta` 在全部现网 rollout 中均位于 **首行**，整文件读取本身是浪费。

## 修复内容

- **session_meta 首行热路径**
  - `_rewrite_rollout_session_meta_provider` 只读首行；provider 未变则立即返回。
  - managed provider id 等长时原地补丁首行，不重写多 MB 正文。
  - 长度变化时流式拼接首行 + 正文（不把整文件读进 RAM）。
  - 仅对 ≤4MB 且首行不是 `session_meta` 的异常文件回退全量扫描。
- **warm launch 减负**
  - `codex_for_tui_runtime_sessions_linked`：runtime 的 sessions/history 已链到 control home 时，跳过重复 `seed-shared-sessions` 与 legacy importer。
  - V2 热启动：`config-profiles-v2/index.json` 已是 schema 2 时，跳过多余的引擎 `status` 进程，直接 `profile launch`。
- **2.5.19 能力保持**
  - 中转站只含模型策略 / API / Key；上下文/压缩/权限全站共用。
  - `sanitize_service_tier`、legacy 指纹去重、provider fast marker、安全删除 runtime。

## 本机验证（热补丁后）

- 94MB 文件 noop 改写：约 **1ms**（旧约 1.3s）
- 94MB 同长 provider 原地补丁：约 **40ms**（旧约 1.8s+ 且会重写整文件）
- 全量 dual-sync（93 文件）：约 **0.28s**（旧约 2.3s）
- 正确性：改写后正文字节不变；首行 provider 可逆

> 用户墙钟「半分钟 → 可接受」仍需安装 APK 后确认；未确认前不宣称产品侧完全修好。

## 版本标识

- `versionName=2.5.20`
- `versionCode=86`
- runtime epoch：`apk-2.5.20`
- Codex binary：`0.144.1-zh.1`（与 2.5.19 相同固定制品）

## 升级说明

覆盖安装本版 APK 后打开 App。首次启动按新 epoch 完成 support/runtime 升级。之后再启动 Codex，即使会话库很大，provider dual-sync 也不应再整文件吞掉启动时间。若仍明显偏慢，请反馈是「输入 `codex` 到 TUI 出现」还是「打开 App 到 shell 就绪」。