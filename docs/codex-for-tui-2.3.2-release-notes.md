# Codex for TUI 2.3.2 Release Notes

发布日期：2026-07-07

## 重点

2.3.2 是 2.3.1 后的安全与稳定补丁，面向已经使用 2.x 正式版的用户。覆盖安装后重新打开终端即可同步 APK 内置桥接命令；普通启动仍不会自动联网更新脚本、刷新模型目录或覆盖用户配置。

## 加固

- Release 构建必须使用 `ANDROID_RELEASE_*` GitHub Secrets/离线签名输入；仓库内 keystore/testkey fallback 被禁用。
- GitHub Actions 会在上传前校验 packageName、versionCode、versionName、`debuggable=false` 和 2.x 正式签名证书 SHA-256。
- `codex-dev-transfer export` 默认排除 `auth.json`、API key、Codex sessions、Cookie、WebView/db/no_backup/browser 等敏感登录态；确需迁移敏感数据时必须显式 `--include-secrets --yes`。
- `codex-dev-transfer import` 增加路径和文件类型白名单，拒绝绝对路径、`..`、symlink、hardlink 和 device 节点。

## 稳定性

- 普通启动保持不自动更新脚本、不刷新模型目录、不覆盖用户手写配置；首次无配置仍进入初始化流程。
- 快捷授权菜单默认回车跳过，只有明确输入 `1` 才写 requirements/hooks。
- 配置写入改为临时文件 + 原子替换 + 可恢复备份。
- App session 使用独立 `PROOT_TMP_DIR` 并清理；rootfs 安装增加 lock、ready marker 和原子切换。

## 升级

1. 从 GitHub Releases 下载 2.3.2 正式 APK。
2. 覆盖安装到既有 2.x 正式版。
3. 重新打开 Codex for TUI。
4. 如需要同步最新脚本，手动运行：

```sh
codex 更新
codex-local repair-launcher
```

可选检查：

```sh
codex-doctor
codex-ops status
```

## 回滚

Android 普通覆盖安装不能降低 `versionCode`，因此不能把 2.3.2（`versionCode=45`）直接覆盖安装回 2.3.1（`versionCode=44`）或更低版本。需要回滚时请优先发布“前滚回滚包”（保留目标行为但使用更高 `versionCode`），或在明确会丢失/需迁移数据的情况下卸载后重装旧版。
