# Codex for TUI 2.4.5 发布说明

Codex for TUI 2.4.5 聚焦冷启动体验：默认进入 shell、减少启动噪声、加快日常冷启动，并厘清新用户 / 老用户流程。

## 关键修复

### 1. 默认不再自动进入 Codex

- 旧行为：`CODEX_FOR_TUI_AUTO_START` 默认为 `1`，安装完成后直接 `exec codex`。
- 新行为：默认 `0`，进入 shell，并打印一行就绪提示：`环境就绪 · … 输入 codex 启动`。
- 设置页新增「启动时自动进入 Codex」（默认关）；开启后恢复旧行为。
- 新会话通过 `MkSession` 注入 `CODEX_FOR_TUI_AUTO_START=0|1`。

### 2. 启动噪声 / 黄色警告

- 过滤 proot 无害绑定警告：`can't sanitize binding /proc/.../fd`。
- 默认工作目录改为 `/root/workspace`（可用 `CODEX_FOR_TUI_WORKSPACE` 覆盖），避免 cwd=`$HOME` 时把用户配置误判为 project-local，从而减少黄色  
  `Ignored unsupported project-local config keys … model_provider, model_providers`。
- launcher 启动真实 Codex 时也会 `cd` 到 workspace。
- 去掉「Codex 已安装，直接启动。」等多余 info。

### 3. 日常冷启动更快

- APK 环境升级在 `quick_complete` 命中后立即静默退出，不再每次冷启动触发联网 `best_effort_refresh`。
- 模型目录联网刷新仍只在**真实升级事务完成后**尽力执行一次。

### 4. 配置 / 会话 / 压缩（说明，行为保持）

- 各配置档（V2 profile）继续独立：runtime、sessions、auth、catalog、SQLite（按 profile + version + epoch + 二进制 SHA）。
- 不同配置**不属于**同一会话池；`resume` 按当前 provider/profile 过滤。
- 压缩策略默认 `follow-model`（跟随模型上下文），可在配置模式设为固定 token。
- 2.4.3 的 `tool_mode` 规范化与 2.4.4 文件托盘「附加说明」继续保留。

## 新用户 vs 老用户流程

### 新用户

1. 安装 APK，打开 App。
2. 首次确认安装 → 下载/安装固定 Codex 与依赖。
3. 进入 **shell**（默认不自动进 Codex），看到就绪提示。
4. 需要时运行 `codex`；未配置时走配置向导 / 官方登录。
5. 管理站点与压缩：`codex 配置模式`。

### 老用户升级（2.4.x → 2.4.5）

1. 覆盖安装 2.4.5 APK（`versionCode=60`）。
2. 首次打开完成离线 APK 环境升级（失败回滚，下次重试）。
3. 之后日常冷启动：`quick_complete` 秒退 → 可选就绪一行 → shell。
4. 配置、会话、模型目录按 profile 隔离保留；需在对应配置下 `resume`。
5. 若仍想打开即进 Codex：设置 → 开启「启动时自动进入 Codex」。

## 版本与固定产物

- `versionName=2.4.5`
- `versionCode=60`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.5`

Android 不支持普通覆盖安装降级。从 2.4.5 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
