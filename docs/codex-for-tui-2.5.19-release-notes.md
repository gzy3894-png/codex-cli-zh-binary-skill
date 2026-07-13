# Codex for TUI 2.5.19

2.5.19 是 2.5.18 后的配置模式 / 启动性能 / 本机配置清理热修。2.5.18 已恢复原生 `/resume` 跨站列表；本版聚焦「只保留中转站差异字段、通用策略全站共用」，并修掉 krill 的无效 `service_tier=high` 与升级反复导入 `-legacy` 站。

## 修复内容

- **配置模式心智模型**
  - 菜单文案明确：中转站只含模型策略 / API / Key；上下文、压缩、权限等为通用项（全站共用）。
  - 选择列表隐藏 `-legacy*` 噪声站，并展示 base_url。
- **统一配置格式**
  - `model_providers` 改为站级专属：激活时整表替换为当前站 managed provider，不再把孤儿 `[model_providers.custom]` 合并进 common / runtime。
  - `strip_managed_fields` 始终剥离 `model_providers`，避免跨站泄漏。
- **krill high 错误**
  - 新增 `sanitize_service_tier`：仅允许空或 `priority`；`high`/`default`/`flex` 等会在 materialize 时剥掉。
- **启动变快**
  - `sync_provider_visibility(..., fast=True)`：provider 与 sessions mtime 未变时跳过全量 dual-sync（约 3s → ~0.5s 热启动）。
- **升级不再刷 `-legacy`**
  - `legacy_profile_already_imported` 按 name / `name-legacy*` / base_url 指纹去重，避免 APK 升级反复再导入 v1 `config-profiles`。
- **删除中转站更干净**
  - `profile delete` 删除整棵 runtime_home，不再只删部分文件。

## 版本标识

- `versionName=2.5.19`
- `versionCode=85`
- runtime epoch：`apk-2.5.19`
- Codex binary：`0.144.1-zh.1`（与 2.5.18 相同固定制品）

## 升级说明

覆盖安装本版 APK 后打开 App。首次启动会按新 epoch 完成 support/runtime 升级。配置模式应只显示真实中转站；krill 不再因 `service_tier=high` 报错；再次打开 Codex 时启动应明显更快。若本机仍有历史噪声站，可在配置模式删除，或沿用升级前已清理的 grok2 / krill / pipi 三站。
