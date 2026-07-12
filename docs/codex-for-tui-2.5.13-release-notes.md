# Codex for TUI 2.5.13

2.5.13 是 2.5.12 后的 P0 正式前滚热修，重点修复启动台不可用、会话目标串绑、历史 registry 补扫和 Default 模型/思考等级不持久的问题。

## 修复内容

- 启动台只作为永久兜底窗口；同一 App 进程内的 Activity/TerminalView 重建会重新附着当前仍存活的工作窗口，不再强制抢回启动台。
- 文件托盘、文本托盘和虚拟键统一从 `SessionService` 解析显式 live target，再把目标作为参数传下去，避免“发送到启动台”或串到旧报错窗口。
- Codex/Claude/Grok 对话 registry 和 live PTY 继续保持平级模块；关闭窗口不删除 CLI 历史，点击历史仍通过真实 UUID resume。
- Codex 历史扫描增加 0/2/5/10/20/40/60/90 秒有限启动重扫，打开侧栏也会即时刷新，覆盖迁移完成后的 UUIDv7 rollout 会进入 registry。
- `codex-session-defaults` 通过 Codex hook 只记录 Default 模式下结构化的 `thread_settings_applied`，并用 profile generation 防止旧窗口污染新 profile；下一次启动会把最近选择的 model/reasoning 应用为默认值。
- 自动 `sync-runtime` 不再从旧 runtime 反向导入 model/provider/reasoning；配置删除的通用字段不会被旧 runtime-local overlay 复活。
- 覆盖升级会写入二进制 build-key 缓存，普通启动不再反复计算大二进制 SHA；并修复 `/usr/local/bin` 的 `/etc/profile.d/codex-zh.sh` PATH 片段。
- `/root` 已信任时会窄继承到 `/root/workspace`，避免统一工作区下 Codex 启动信任提示打断。
- GitHub Actions 仅构建正式 release APK，不再构建或上传 test APK。

## 验收重点

- 覆盖安装后打开 App，启动台应可输入 `codex` 并新建工作窗口；切屏回来不应抢回启动台。
- 文件托盘点“发送”必须进入当前显式会话，不进入启动台。
- `codex resume` 应能看到旧 UUIDv7 历史；侧栏 Codex 区应包含旧 UUID `019f212d-4b6e-7e93-b3f4-188eefa2657d`。
- 在 Default 模式中切换 model/reasoning 后，新会话应沿用最近选择，而不是回到中等思考。

## 版本

- `versionName=2.5.13`
- `versionCode=79`
- runtime epoch：`apk-2.5.13`
- 包名：`com.gzy3894.codexfortui`
