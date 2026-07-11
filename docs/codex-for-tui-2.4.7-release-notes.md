# Codex for TUI 2.4.7 发布说明

Codex for TUI 2.4.7 是 2.4.6 的前滚体验热修：引导文字输出后干净进入纯 shell，并重做文件托盘多选与短名展示。

## 关键修复

### 1. 引导结束即纯 shell

- 就绪引导仍多行列出 `codex` / `codex 配置模式` / `codex 官方登录` 及结果。
- 引导末尾明确「引导结束，进入 shell」，bootstrap 随即 `exit 0`，由 `init.sh` 交接交互 shell。
- `enter_interactive_shell` 加强：`stty sane`/`echo icanon`（含 `/dev/tty` 回退），并通过 `ENV` 一次性交互 rc 在 ash 启动后再断言回显。
- 目标：避免「还在引导模式」导致输入异常；进入后应是普通可交互 shell。

### 2. 文件托盘多选 + 顶部统一发送

- 每个文件卡片支持勾选（Checkbox）；支持全选/取消全选。
- 托盘顶部统一「发送」按钮（显示已选数量）；去掉每项单独「发送」。
- 批量发送可填一条「附加说明（可选）」；一次提交多条 `类型N[refId] 路径：codex-preview path …`。
- 文本快捷输入格仍可直接发纯文本。

### 3. 临时文件显示名：类型 + 编号

- UI 显示名统一为 `图片1` / `视频2` / `文本3` 这类短名，不再展示超长原文件名或 stamp 前缀。
- 用户点选入库的磁盘缓存改为 `$stamp-img|vid|txt.ext`，文本草稿为 `$stamp-text.txt`。
- 发送到会话的提示优先使用短显示名 + 稳定 `refId`（stamp）。

### 4. 2.4.6 能力继续保留

- 默认 shell-first、proot 噪声过滤、`/root/workspace`、日常 `quick_complete` 静默秒退。
- 默认输入模式仍映射为 `TYPE_NULL`；「旧版兼容」才用 `VISIBLE_PASSWORD`。
- 2.4.3 `tool_mode` 修复与附加说明能力（现为批量确认框）继续保留。

## 新用户 vs 老用户流程

### 新用户

1. 安装 APK，打开 App。
2. 首次确认安装 → 下载/安装固定 Codex 与依赖。
3. 看到多行就绪引导后进入 **纯 shell**。
4. 输入过程应实时显示；回车执行。运行 `codex` 进入 Codex。

### 老用户升级（2.4.x → 2.4.7）

1. 覆盖安装 2.4.7 APK（`versionCode=62`）。
2. 首次打开完成离线 APK 环境升级（失败回滚，下次重试）。
3. 之后冷启动：`quick_complete` 秒退 → 就绪引导 → 纯交互 shell。
4. 文件托盘：勾选多项后点顶部「发送」。
5. 若仍无实时回显：设置 → 输入模式切换「默认」或「旧版兼容模式」试一次。

## 版本与固定产物

- `versionName=2.4.7`
- `versionCode=62`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.7`

Android 不支持普通覆盖安装降级。从 2.4.7 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
