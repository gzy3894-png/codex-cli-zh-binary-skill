# Codex for TUI 2.5.27

2.5.27 是首次安装 Alpine rootfs 解压热修，修复部分 Android 设备首次打开 App 时连续输出：

```text
tar: chown 0:0 ...: Operation not permitted
```

并中止初始化的问题。

## 根因

首次启动在 Android 宿主环境使用 Toybox `tar` 解压 APK 内置 Alpine rootfs。归档文件记录为 `root:root`，而普通 Android App 进程没有把文件 `chown` 为 uid/gid 0 的权限。文件内容已经可以写入 App 私有目录，但 `tar` 在恢复所有者时返回失败。

这不是网络下载失败，也不是缺少 Android 存储权限；申请运行时权限不能授予 `chown root:root` 能力。

## 修复

- rootfs 解压使用 Toybox 与 GNU tar 都支持的 `-o` 选项，忽略归档 uid/gid，让文件保持 App 沙箱用户所有权。
- 解压仍在临时目录完成，成功后写入 ready marker 并原子切换到正式 rootfs。
- 安装锁记录持有进程 PID 与 `/proc` 启动 token。
- 若旧版解压过程中被强制关闭，留下无存活持有者的锁和半成品目录，新版会自动清理并重新安装。
- 增加模拟遗留锁、首次解压、ready marker 与锁释放的回归测试。

## 用户操作

下载并覆盖安装 2.5.27 APK，然后重新打开 App：

- 不要卸载旧 App。
- 不要清除 App 数据。
- 不需要额外申请存储权限。
- 不需要先运行 `codex-update`。

此故障发生在 Alpine 启动和远程脚本更新之前，因此重新安装旧 APK 或只推送远程脚本无法修复，必须使用包含新版 `init-host` 的 2.5.27 APK。

## 版本元数据

- `versionName=2.5.27`
- `versionCode=93`
- runtime epoch：`apk-2.5.27`
- Codex binary：`0.144.1-zh.1`
- 包名：`com.gzy3894.codexfortui`

## 回滚

Android 已安装 `versionCode=93` 后不能普通覆盖降级。若本版出现产品问题，应发布更高 versionCode 的前滚热修，不要求用户卸载或清除数据。
