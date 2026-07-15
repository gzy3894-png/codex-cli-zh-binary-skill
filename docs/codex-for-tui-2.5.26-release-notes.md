# Codex for TUI 2.5.26

2.5.26 是模型默认值与上下文压缩热修，修复 2.5.25 真机上 `/model` 已切换、control 配置仍是旧值，以及低上下文占用切模连续自动 compact。

## 用户可见变化

### 1. `/model` 即时写回配置真源

- Codex 仍先把选择写到当前 profile 的隔离 runtime。
- 交互 launcher 自动启动轻量 `codex-session-defaults watch-runtime`。
- runtime 变化后立即事务更新当前 profile 与 `~/.codex/config.toml`，不再等下一次启动消费 pending 文件。
- 每次写回携带 profile generation；配置模式或其他新会话已改过配置时，旧 watcher 会停止，不能覆盖较新的选择。

### 2. 固定压缩阈值真正生效

Codex 0.144.1 在两个模型的 `comp_hash` 不同时会无条件 auto compact，即使只用了很少上下文。固定策略 materialize 到 runtime 时，本版会清除 runtime 副本中的：

- `comp_hash`
- 模型自带 `auto_compact_token_limit`

profile/control 模型目录仍保留上游值；切回「跟随模型」会恢复。固定模式下只有用户设置的 token 阈值和上下文安全边界能触发自动压缩。

### 3. 只读命令零副作用

`codex --version`、`codex -V`、`codex --help`、`codex -h`、`codex help` 直接调用真实二进制，不再准备 profile runtime，也不会消费待写默认值。

## 回归证据

问题会话在约 57 秒内发生两次 `PreCompact:auto`：

- 第一次约 `8k / 353k`
- 第二次约 `26k / 258k`

两次都紧邻 `thread_settings_applied`，对应 `gpt-5.5.comp_hash=2911` 与 `gpt-5.6-sol.comp_hash=3000` 的切换，而不是达到 token 阈值。

## 版本元数据

- `versionName=2.5.26`
- `versionCode=92`
- runtime epoch：`apk-2.5.26`
- Codex binary：`0.144.1-zh.1`
- 包名：`com.gzy3894.codexfortui`

## 回滚

Android 已安装 `versionCode=92` 后不能普通覆盖降级。若本版安装后出现产品问题，应发布更高 versionCode 的前滚热修；脚本级临时回退可设置：

```sh
CODEX_FOR_TUI_SESSION_DEFAULTS_WATCH=0 codex
```

这只关闭即时默认值同步，不会改写模型目录或会话记录。
