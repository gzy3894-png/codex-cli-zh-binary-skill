# Codex for TUI 2.5.1 发布说明

Codex for TUI 2.5.1 是 **2.5.0 的启动闪退热修**。2.5.0 引入会话隔离后，`SessionNaming` 在类初始化阶段编译了一条非法 Unicode 属性正则，Android ICU 抛出 `PatternSyntaxException`，导致 `ExceptionInInitializerError`，打开 App 即闪退。

## 根因

- 崩溃点：`SessionNaming.<clinit>` → `Regex("[^\\p{L}\\p{N._\\-\\s]+")`
- 设备 log：`PatternSyntaxException: Incorrect Unicode property near index 19`
- 调用链：创建/恢复终端会话 → `SessionIsolation.onSessionCreated` → 触达 `SessionNaming` 类加载 → 主线程崩溃

## 修复

1. 去掉 `\p{L}` / `\p{N}` 等 Unicode 属性正则；标题清洗改为 `Char.isLetterOrDigit` + 明确允许集。
2. `SessionIsolation.onSessionCreated` 增加 `runCatching` 兜底，命名/注册表异常时不再拖垮整 App。
3. 静态门禁禁止 `SessionNaming` 再引入 `\p{L}` / `\p{N` 写法。

## 用户可见

- 2.5.0 的会话隔离能力保留（前缀名、重命名、冷启动恢复、UUID resume 绑定）。
- 可从 2.4.10 或 2.5.0 覆盖安装 2.5.1 后正常打开。

## 版本信息

- `versionName=2.5.1`
- `versionCode=67`
- runtime epoch：`apk-2.5.1`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.1 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装。
