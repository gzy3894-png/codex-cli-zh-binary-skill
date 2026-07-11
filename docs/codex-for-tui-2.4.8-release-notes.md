# Codex for TUI 2.4.8 发布说明

Codex for TUI 2.4.8 是 2.4.7 的前滚热修：引导结束后的纯 shell 固定落在 `$HOME`，并扩大 proot 噪声过滤，避免 ptrace / PROOT_TMP_DIR 警告污染终端。

## 关键修复

### 1. 引导结束后回到 home，而不是 workspace

- 2.4.5 起为减少 Codex project-local 黄字，会把 cwd 设到 `/root/workspace`。
- 在 shell-first 流程里，这会让用户感觉「引导后进了一个莫名其妙的路径」；部分命令（如依赖 home 的 `claude` / 用户口中的 `cloud`）需要先手动 `cd` / `HOME` 才能正常启动。
- 2.4.8：交互 shell 交接前强制 `cd "$HOME"`（含 ENV 一次性 rc 再断言一次）。
- `CODEX_FOR_TUI_WORKSPACE=/root/workspace` 仍导出，**仅**供 `codex` launcher 启动时使用，shell 本身不再停在 workspace。

### 2. 扩大 proot 噪声过滤 + 稳定 PROOT_TMP_DIR

- 过滤更多已知无害警告：
  - `proot warning: ptrace(...)`
  - `proot warning: can't set tracee registers ...`
  - `proot info: Please set PROOT_TMP_DIR ...`
- `PROOT_TMP_DIR` 改放到 `$PREFIX/local/proot-tmp/<session>/`，避免 App 启动清理 `cache/tmp` 时误删 proot 私有临时目录。
- `init-host` 在 env 缺失或不可写时自动回退创建可写 `PROOT_TMP_DIR`。
- App 启动清理改为只删 `cache/tmp` 下的零散文件，不再递归清空整个临时树。

### 3. 2.4.7 能力继续保留

- 引导结束「引导结束，进入 shell」→ 纯交互 shell（`stty` + `ash -i` + ENV rc）。
- 文件托盘多选、顶部统一发送、短名 `图片N`/`视频N`/`文本N`。
- 默认 shell-first、日常 `quick_complete` 静默秒退、`tool_mode` 修复。

## 新用户 vs 老用户流程

### 新用户

1. 安装 APK，打开 App。
2. 首次确认安装 → 下载/安装固定 Codex 与依赖。
3. 看到就绪引导后进入 **纯 shell**，提示符路径应为 `/root`（home），不是 `/root/workspace`。
4. 直接运行 `codex` / `claude` 等命令，无需先手动改路径。

### 老用户升级（2.4.x → 2.4.8）

1. 覆盖安装 2.4.8 APK（`versionCode=63`）。
2. 首次打开完成离线 APK 环境升级（失败回滚，下次重试）。
3. 冷启动后确认：引导结束 → `pwd` 为 `/root`。
4. 若仍看到 proot 警告刷屏：完全划掉 App 后重开一次（让新 `init-host` / `PROOT_TMP_DIR` 生效）。

## 版本与固定产物

- `versionName=2.4.8`
- `versionCode=63`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.8`

Android 不支持普通覆盖安装降级。从 2.4.8 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
