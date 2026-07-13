# Codex for TUI 2.5.21

2.5.21 是 2.5.20 后的**配置模式结构**优化。2.5.20 已修好大会话 dual-sync 启动慢；本版把「站级 vs 通用」从文案落到可操作的字段结构。

## 目标结构

| 层级 | 字段 | 切换时是否变 |
|---|---|---|
| **中转站** | 名称、模型策略（模型 + 推理）、API Base URL、Key、模型目录 | 随站切换 |
| **通用** | 上下文/压缩策略、权限/沙箱、TUI、features、projects | 全站共用 |

## 用户可见变化

- **主菜单分区**：`—— 中转站 ——` / `—— 通用（全站共用）——` / `—— 退出 ——`。
- **当前摘要**：顶部显示当前站模型策略与 API，以及全站压缩策略标签。
- **字段级编辑**：编辑中转站不再强制整站向导；可单独改名称 / API / Key / 模型策略，也可选「全部重设」。
- **查看中转站**：分区展示站级字段与通用压缩策略（标明全站共用）。
- **压缩策略**：文案明确「全站共用，不随中转站切换」；引擎侧 `compact_policy` 只写 `index.json`，不再写入各站 `profile.json`。

## 引擎

- `create_profile_directory` / migrate / repair 不再把 `compact_policy` 镜像进站级 meta。
- `redact_profile` 剥离遗留的站级 `compact_policy`；`materialize` / APK repair 顺带清理旧字段。
- `profile list` / `show` 附带全局 `compact_policy`，供菜单摘要显示。
- 站级仍只 materialize：`model` / `model_reasoning_effort` / `model_provider` / `model_providers` / `model_catalog_json` + 全局 compact 阈值。

## 版本标识

- `versionName=2.5.21`
- `versionCode=87`
- runtime epoch：`apk-2.5.21`
- Codex binary：`0.144.1-zh.1`（与 2.5.20 相同固定制品）

## 升级说明

覆盖安装本版 APK 后打开 App。配置模式进入后应看到分区菜单与当前站/通用摘要；编辑中转站可只改一个字段。压缩策略改完后，切换 grok2 / krill / pipi 不应再出现「每站一份压缩」的错觉。
