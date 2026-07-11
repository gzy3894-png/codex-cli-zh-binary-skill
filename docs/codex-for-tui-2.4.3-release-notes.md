# Codex for TUI 2.4.3 发布说明

Codex for TUI 2.4.3 是 2.4.2 的紧急前滚热修版，修复真机覆盖安装后工具调用全面失败，以及会话看起来“全部消失”的问题。

## 关键修复

### 1. aarch64-musl 上 `gpt-5.6-*` 工具调用全挂

2.4.2 随包模型目录把 `gpt-5.6-sol` / `gpt-5.6-terra` / `gpt-5.6-luna` 标成了 `tool_mode = code_mode_only`。  
但 Android/Alpine 使用的 `aarch64-unknown-linux-musl` Codex `0.144.1` 构建没有 V8 code mode 运行时，因此任意工具调用都会在执行前失败：

```text
code mode is unavailable in this aarch64-unknown-linux-musl build
```

2.4.3 做了两层修复：

- 随包 `openai-models.json` 清除上述模型的 `code_mode_only`。
- 配置引擎在写入/重建/物化任何模型目录时，统一把 `tool_mode = code_mode_only` 规范为 `null`，避免后续升级、刷新或 profile 物化再次写回坏值。

修复后，`gpt-5.6-sol` 等模型会重新走普通 `shell_command` 工具路径。

### 2. 会话“消失”与 profile runtime 隔离

2.4.2 已将 sessions / SQLite 按 profile 隔离。  
若活动配置被切到会话很少的站点（例如 `krill`），`codex resume` 会显示为空，但历史会话仍在原 profile runtime 中（例如 `root`）。

2.4.3 不撤销隔离；它保证：

- 升级仍会重建可用模型目录，使工具在所有 profile 上恢复。
- 文档明确：恢复历史会话应先切回对应配置，或使用 `codex resume --all` / 直接 `codex resume <UUID>`。

## 仍保留的 2.4.2 能力

- APK 覆盖安装后的离线、原子、可回滚完整环境升级。
- 固定 Codex `0.144.1-zh.1` ARM64 musl 二进制。
- `/root/.codex` 作为统一 `CODEX_HOME`。
- profile 独立 runtime / sessions / SQLite。
- `apk-2.4.3` runtime epoch，避免误开旧 SQLx 数据库。
- `codex-auto-*` 隐藏，`/model` 直接进入完整普通模型页。

## 升级方式

已安装 2.4.2 或更早版本的用户：

1. 从 GitHub Releases 下载并覆盖安装 2.4.3 APK。
2. 打开 App，等待首次 APK 环境升级完成。
3. 启动 Codex 后确认：
   - `gpt-5.6-sol` 能执行 shell 工具。
   - 历史会话在对应 profile 下可 `resume`。

无需手动运行 `codex 更新`、`codex-local repair-launcher` 或手工改 `CODEX_HOME`。

若你在 2.4.2 上已经手工 patch 过模型目录，2.4.3 升级会再次规范化目录，结果应与热修一致。

## 版本与固定产物

- `versionName=2.4.3`
- `versionCode=58`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.3`

Android 不支持普通覆盖安装降级。从 2.4.3 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
