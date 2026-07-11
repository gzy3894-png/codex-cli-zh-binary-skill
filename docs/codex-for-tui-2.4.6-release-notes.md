# Codex for TUI 2.4.6 发布说明

Codex for TUI 2.4.6 是 2.4.5 的前滚体验热修：把 shell 就绪引导写清楚，并修复终端输入过程中看不到已输入内容（回车才显示并执行）的问题。

## 关键修复

### 1. 多行就绪引导

- 旧行为：一行长文案 `环境就绪 · 活动配置: … · 输入 codex 启动…`，窄屏换行后难读。
- 新行为：多行提示，明确「输入什么」以及「会得到什么结果」：
  - `codex` → 启动 Codex TUI
  - `codex 配置模式` → 管理站点、模型与压缩策略
  - `codex 官方登录` → 设备码登录官方账号（可选）
- 仍在 stdout 输出，避免被当成警告样式。

### 2. Shell 输入实时回显

- 进入 shell 时改为交互式 `ash -i`，并在可用时执行 `stty sane` / `echo icanon`，保证 PTY 本地回显与行编辑。
- 修正默认输入模式与 stock termux `TerminalView` 的映射：
  - 默认 / 严格终端 → `TYPE_NULL`（按键即时送入终端，由 shell 回显）
  - 「旧版兼容模式」→ `VISIBLE_PASSWORD`（三星键盘字符模式，仅在默认无实时回显时使用）
- 2.4.5 的默认路径误把「推荐」模式走成 VISIBLE_PASSWORD，部分输入法会把整行攒到回车才提交，表现为「输入过程中什么都没有」。

### 3. 2.4.5 能力继续保留

- 默认 shell-first（`CODEX_FOR_TUI_AUTO_START=0`），设置可恢复自动进 Codex。
- 过滤 proot `can't sanitize binding`；工作目录 `/root/workspace`。
- 日常冷启动 `quick_complete` 静默秒退。
- 2.4.3 `tool_mode` 修复与 2.4.4 文件托盘「附加说明」继续保留。

## 新用户 vs 老用户流程

### 新用户

1. 安装 APK，打开 App。
2. 首次确认安装 → 下载/安装固定 Codex 与依赖。
3. 进入 **shell**，看到多行就绪引导。
4. 输入过程应实时显示；回车执行。运行 `codex` 进入 Codex。

### 老用户升级（2.4.x → 2.4.6）

1. 覆盖安装 2.4.6 APK（`versionCode=61`）。
2. 首次打开完成离线 APK 环境升级（失败回滚，下次重试）。
3. 之后冷启动：`quick_complete` 秒退 → 多行就绪引导 → 交互 shell。
4. 若仍无实时回显：设置 → 输入模式切换「默认」或「旧版兼容模式」试一次。
5. 若仍想打开即进 Codex：设置 → 开启「启动时自动进入 Codex」。

## 版本与固定产物

- `versionName=2.4.6`
- `versionCode=61`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.6`

Android 不支持普通覆盖安装降级。从 2.4.6 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
