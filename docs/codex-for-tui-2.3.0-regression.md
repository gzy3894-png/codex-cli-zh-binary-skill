# Codex for TUI 2.3.0 稳定化回归清单

日期：2026-07-06

目标：2.3.0 不是继续堆大功能，而是把 2.2.9 已经发布的安装、配置、文件托盘、协作浏览器、Custom Tabs、RTK/context、会话折叠和终端性能底座做成可重复验证的发布门禁。

## 发布原则

1. 本地只运行 shell 语法、静态守卫和 smoke 脚本；不在本地跑 Gradle/APK 构建。
2. APK、正式签名、Release asset 和 SHA256SUMS 只通过 GitHub Actions 生成。
3. 2.x 正式签名证书 SHA-256 必须保持：

```text
a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc
```

4. 不打印 token、cookie、API key、`auth.json` 或网页登录态内容。
5. 真机门禁失败时优先最小修复；遇到签名异常、破坏性 git 操作或无法小修的 P0/P1 问题时停止确认。

## 本地非 APK 门禁

在仓库根目录执行：

```sh
sh -n android-app/core/main/src/main/assets/codex-browser
sh -n android-app/core/main/src/main/assets/codex-preview
sh -n android-app/core/main/src/main/assets/codex-panel
sh -n android-app/core/main/src/main/assets/codex-session
sh -n android-app/core/main/src/main/assets/codex-rtk
sh -n android-app/core/main/src/main/assets/codex-context
sh -n tests/codex-for-tui-browser-smoke.sh
sh -n tests/codex-for-tui-device-smoke.sh
sh -n tests/codex-for-tui-installed-device-smoke.sh
sh tests/codex-for-tui-static-guards.sh
sh tests/codex-for-tui-installer-smoke.sh
git diff --check
```

## 真机自动化门禁

已安装并打开正式版后，在 App 内 Alpine 终端执行：

```sh
CODEX_TUI_REQUIRE_HOOKS=1 \
CODEX_TUI_EXPECTED_VERSION_CODE=43 \
tests/codex-for-tui-installed-device-smoke.sh

tests/codex-for-tui-browser-smoke.sh
```

如果要把真实视频预览纳入自动门禁，额外提供一个可读视频路径：

```sh
CODEX_TUI_SMOKE_VIDEO_PATH=/storage/emulated/0/Download/Codex/sample.mp4 \
CODEX_TUI_REQUIRE_HOOKS=1 \
tests/codex-for-tui-installed-device-smoke.sh
```

## 手动/半自动回归矩阵

| 区域 | 通过标准 | 证据 |
| --- | --- | --- |
| 安装/更新/首启 | 覆盖安装后能打开终端，`pm` 版本号与 Release 资产一致，普通启动不自动更新脚本/刷新模型/覆盖配置 | `pm list packages --show-versioncode`、启动日志、`codex-local doctor` |
| Codex 启动 | `codex` 可进入 TUI；缺配置时只触发配置向导；已有配置时不改写用户手写配置 | 终端行为、`~/.codex/config.toml` 不被菜单文字污染 |
| 配置管理器 | 新建、选择、编辑、查看、删除、退出返回上层；新建/编辑后主动询问保存；切换前保护未保存修改 | `codex 配置模式` 真机操作 |
| 快捷授权 | `approval_policy = "never"` 与 `sandbox_mode = "danger-full-access"` 写入后真实生效；RTK/context hooks 由 requirements 托管 | `codex-rtk status`、`codex-context status`、读写 smoke |
| 文件托盘 | 图片、文本、视频可加入；长文本不刷屏；用户文本框发送后清空；支持选择、删除、清空、折叠、分享事件 | `codex-preview`、`codex-panel status/events`、真机 UI |
| 浏览器 WebView | 默认后台打开；`present/collapse` 信号正确；多标签可切换；Cookie/WebStorage 可复用；JS/DOM/截图可用 | `tests/codex-for-tui-browser-smoke.sh` |
| 后台截图 | `visible=0 collapsed=1` 时能截到真实网页内容，不自动展开托盘 | `codex-browser screenshot --push --background` + 视觉检查 |
| Custom Tabs/Auth | `auth-open` 只创建任务卡；用户完成/取消/折叠/重开均有回传；取消后普通浏览不残留 auth 状态 | `codex-browser auth-open/auth-cancel/open` |
| 预览托盘清理 | 托盘流可清空；删除单项后 active item 正确；清空不会污染后续发送 | `codex-preview clear/remove/status` |
| 会话折叠 | 时间线可折叠/展开/清空；折叠只影响展示，不伪造或删除终端真实上下文 | `codex-session status/events` |
| 终端输出性能 | 高频输出不明显卡死；perf 状态可读；bridge 轮询不因后台/Custom Tabs 停止 | `$PREFIX/local/perf/terminal.status`、`seq/yes head` 手测 |

## 2.3.0 完成条件

1. 上述本地非 APK 门禁通过。
2. GitHub Actions 构建正式 APK、测试 APK、RTK musl artifact 全通过。
3. Release APK SHA256SUMS 校验通过，签名证书 SHA-256 与 2.x 正式证书一致。
4. 真机自动化门禁通过，关键手动矩阵没有 P0/P1 遗留。
5. README、CHANGELOG 和 Release notes 明确写出 2.3.0 的稳定化范围、升级方式、回滚依据和已知边界。
