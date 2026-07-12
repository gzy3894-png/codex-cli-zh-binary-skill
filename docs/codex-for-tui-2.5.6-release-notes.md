# Codex for TUI 2.5.6 发布说明

Codex for TUI 2.5.6：配置物化改为「通用底稿 ⊕ profile 变量补丁」，自动压缩策略改为全局固定策略真源，避免切中转站/再物化冲掉通用配置。

## 核心改动

### 1. common ⊕ managed 补丁物化

此前 `materialize_profile` 以各 profile 的 `legacy-config.toml` 整包快照为底稿，再盖 managed 字段。结果是：

- 审批/沙箱/TUI/features 等“通用项”被 profile 冻住；
- 改一次通用配置，切站或 relaunch 可能被旧 legacy 盖回；
- 压缩阈值等全局策略被迫同步到每个 profile。

2.5.6 起：

1. 从 control `CODEX_HOME/config.toml` 读取 **common**（剥离 managed 变量）；
2. 仅补丁写入 profile 变量：`model` / `model_provider` / `model_reasoning_effort` / `model_catalog_json` + provider 段；
3. 应用 **全局** `compact_policy`；
4. `legacy-config.toml` 仅作迁移/备份，**不再**作为物化底稿。

Runtime `config.toml` 在 relaunch 时保留非 managed 的本地附加键（补丁合并，非整文件覆盖语义）。

### 2. 自动压缩策略全局化

- `config-profiles-v2/index.json` 的 `compact_policy` 为唯一真源；
- `compact-policy fixed|follow-model` 只改 index + 当前 control/runtime 物化；
- profile `profile.json` 内的 compact 字段不再参与决策（兼容保留，可忽略）。

推荐固定阈值示例（针对 gpt-5.6 系 276k 翻倍计费）：

```sh
python3 "$engine/libexec/codex-config-engine.py" \
  --codex-home "$CODEX_HOME" compact-policy fixed 250000
```

### 3. 供应商/中转站应只承载变量

Profile（`managed.toml`）继续只表达经常变动的部分：

- base_url / provider_id
- API key / auth helper
- 默认 model
- 思考等级
- 可选 catalog

其余（approval、sandbox、features、TUI、compact）走通用配置。

## 版本信息

- `versionName=2.5.6`
- `versionCode=72`
- runtime epoch：`apk-2.5.6`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.6 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装。

## 安装后建议自测

1. 覆盖安装 2.5.6 后打开 App，确认可正常进入 shell / 启动 codex。
2. 设置全局压缩：`compact-policy fixed 250000`，`codex-context status` 应显示 `model_auto_compact_source=config-fixed` 且阈值为 250000。
3. 切换另一个中转站 profile 再切回：通用项（如 TUI 状态栏、approval/sandbox、compact 阈值）应保持，不应被旧 legacy 冲掉。
4. 侧栏关窗仍应先落盘 registry（2.5.5 行为保留），冷启动不复活已删窗口。
5. 切换不同 Codex 配置：CLI 会话列表仍共享（2.5.4+）。
