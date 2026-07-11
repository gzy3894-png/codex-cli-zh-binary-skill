# Codex for TUI 2.4.9 发布说明

Codex for TUI 2.4.9 针对 2.4.8 的「打开一片空白 / 引导结束后卡半天」体感问题做热修：启动立刻有文案、避免每次会话重写大型 managed 脚本、引导后 shell 交接有明确进度。

## 核心修复

### 1. 启动不再空白

- `init-host` 在任何 rootfs / proot 工作前立刻打印：`Codex for TUI：正在启动…`
- `init` 进入 guest 后立刻打印：`Codex for TUI：环境已就绪，正在初始化…`
- 升级检查、依赖准备阶段也有短提示，避免「隔很久才有字」。

### 2. 每次进 App / 开新会话不再卡半天

- 根因：`MkSession` 每次创建会话都会无条件从 assets 重写全部 managed 脚本，其中包含约 **6.7MB** 的 `rtk` 二进制。
- 2.4.9：按 `versionCode/versionName` 做 stamp；已同步且文件完整时直接跳过。
- 对可获取 `openFd` 长度的大文件，长度一致时跳过重写。
- `UpdateManager` 同样改为 stamp 跳过，避免 App 启动重复重写关键脚本。

### 3. 引导文字后不再「假死」

- 引导结束进入 shell 前打印：`正在进入交互 shell…`
- `stty` 仅在真实 tty 上调用，避免无 controlling tty 时的异常等待。
- 交互 shell 使用非 login 的 `ash -i`，避免二次加载 `/etc/profile` 放大延迟。

### 4. 其它清理

- APK 环境升级成功后删除 `work/` 暂存树（设备上曾残留约数百 MB）。
- 自动清理指向已删除 `cache/tmp/codex-tui-static-*` 的脏 `profile.d/codex-zh.sh` PATH 注入。

## 2.4.8 能力继续保留

- 引导结束后纯 shell 落在 `$HOME`（`/root`）。
- workspace 仅给 `codex` launcher。
- proot 噪声过滤、`PROOT_TMP_DIR` 稳定路径、文件托盘多选、shell-first 默认。

## 新用户 vs 老用户

### 新用户

1. 安装 2.4.9 APK。
2. 打开 App 应立刻看到「正在启动…」类提示，而不是长时间空白。
3. 引导结束后应很快出现 shell 提示符（路径 `/root`）。

### 老用户（2.4.8 → 2.4.9）

1. 覆盖安装 `versionCode=64`。
2. 首次打开完成离线环境升级（成功后会清理升级 work 目录）。
3. 冷启动 / 新会话确认：
   - 不再长时间空白
   - 引导结束到 root 提示符明显更快
4. 若仍异常：完全划掉 App 后重开一次。

## 版本与固定产物

- `versionName=2.4.9`
- `versionCode=64`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`
- runtime epoch：`apk-2.4.9`

Android 不支持普通覆盖安装降级。从 2.4.9 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
