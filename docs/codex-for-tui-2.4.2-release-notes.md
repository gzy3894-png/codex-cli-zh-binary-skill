# Codex for TUI 2.4.2 发布说明

Codex for TUI 2.4.2 是一次完整环境升级版。它修复 2.4.0/2.4.1 中“APK 更新了，但 Codex 二进制、launcher、配置引擎、模型目录和本地数据库仍可能停留在不同版本”的升级漂移。

老用户覆盖安装 2.4.2 APK 后只需打开 App。首次启动 Codex 前，App 会使用 APK 内置载荷离线完成环境升级，不再要求用户手动运行 `codex 更新`、`codex-local repair-launcher`、进入配置模式，或手工设置 `CODEX_HOME`。

## APK 一步升级

- APK 内置固定 Codex `0.144.1-zh.1` ARM64 musl 归档、完整受管脚本、launcher、配置引擎和模型能力目录。
- 升级器在 Codex 启动前运行；环境升级未完成时不会继续进入 Codex。
- 全新 rootfs 或旧环境缺少 Python 时，App 会在首次安装确认后自动安装 `python3`，单次启动最多尝试 3 次，随后继续 APK 环境升级，不要求用户输入安装命令；连续失败会阻止 Codex 启动，并在下次打开 App 时重新尝试。
- APK 载荷通过 manifest、归档 SHA-256 和二进制 SHA-256 校验，损坏或版本不匹配会在安装受管文件前被拒绝。
- 受管二进制、launcher 和脚本先暂存再原子切换；配置迁移单独创建恢复点。
- 升级失败会恢复旧二进制、launcher、脚本和配置，保留失败报告，并阻止 Codex 启动；下次打开 App 自动重试。
- 两个终端同时打开时使用同一升级锁串行执行，不会重复迁移或生成重复配置。
- 遗留空锁、损坏 PID 或 PID 复用会通过进程启动标识识别并自动回收，不会长期卡住后续启动。
- 核心离线升级成功后，只对当前第三方站点尽力联网刷新一次模型 ID；失败保留离线重建目录，不阻塞启动。

完成标记存在后，日常启动不会再次更新脚本、替换二进制、请求 `/models` 或覆盖用户手写配置。

## 配置与 `CODEX_HOME`

- Android 会话和升级入口统一使用 `HOME=/root`、`CODEX_HOME=/root/.codex`，不再依赖用户手工输入环境变量。
- `/root/.codex/config.toml` 被视为升级时的当前真实配置，并导入为活动 V2 profile。
- 旧 V1 `config-profiles/current` 只作为历史配置来源保留，不再覆盖根配置，也不再作为 launcher fallback。
- 每个 V1 profile 会导入新的独立 runtime；原 V1 配置和模型目录不会被升级验证改写，V1/V2 混合状态也会补迁尚未导入的 V1 profile。
- 2.3.11 V1、2.4.0 中断/污染状态、2.4.1 故障现场和正常 V2 都通过同一个事务升级入口处理。
- 用户手写 TOML 注释、未知字段、认证信息、固定压缩阈值和旧 profile 保留。
- 旧值 `model_auto_compact_token_limit = 220000` 迁移为“跟随模型”；其他正整数固定阈值按 profile 保留。
- 根目录已有 sessions、history、archived sessions 和 shell snapshots 会复制到根配置独立 runtime；SQLite、FIFO、软链接和插件临时数据不会进入新 runtime。
- 旧 runtime 中指向根 sessions/history 的软链接会拆除并复制为常规文件，避免不同配置继续共享会话状态。

## `/model` 与推理强度

- 固定能力来源仍为 Codex `0.144.1` 对应的 `rust-v0.144.1` 目录。
- 第三方 `/models` 只提供可用模型 ID；推理等级、默认值、上下文窗口和工具能力由固定能力目录合并。
- 所有 `codex-auto-*` 辅助模型标记为隐藏。
- 真实 Codex PTY 门禁确认 `/model` 首层直接显示完整普通模型选择页，不再进入 auto 快捷页。
- `gpt-5.6-sol` 固定为：
  - 上下文窗口：`372000`
  - 默认推理等级：`low`
  - 支持等级：`low`、`medium`、`high`、`xhigh`、`max`、`ultra`
- 已保存但不受当前模型支持的推理等级会回落到该模型的上游默认值，并写入升级报告。

## 会话与 SQLite 隔离

- 每个 profile 使用独立 runtime home、sessions、history、认证和模型目录。
- SQLite 路径按 profile、Codex 版本、APK 运行世代和二进制 SHA 隔离。
- 2.4.2 使用新的 `apk-2.4.2` runtime epoch，即使 Codex 版本号和二进制 SHA 与旧版相同，也不会打开 2.4.0/2.4.1 创建的旧 SQLx 数据库。
- 切换到另一个配置站点后启动新对话，不会终止或污染同终端中已经运行的旧站点会话。

## 自动门禁

发布前自动门禁覆盖：

- shell 语法、Python 编译、工作流 YAML 和静态守卫。
- 配置 V2 CRUD、UI、V1 迁移、崩溃恢复、运行时同步和用户配置保留。
- 2.3.11 V1、2.4.0 中断/污染、2.4.1 真实故障、正常 V2、缺失二进制、损坏载荷、损坏 V2 状态和双终端并发升级。
- 升级故障注入后的二进制、launcher、脚本和配置完整回滚。
- 完成标记写入前的晚期故障也会验证原 V1 目录未被修改；遗留空锁和 V1/V2 混合状态纳入升级矩阵。
- 真实 `0.144.1-zh.1` 二进制解析生成目录。
- 真实 PTY `/model` 首层页面和 `gpt-5.6-sol` 六档推理强度。
- CI 中通过 QEMU 再运行真实 ARM64 parser 与 PTY 门禁。
- Debug/Release APK 内载荷、manifest、归档 SHA、二进制 SHA、包名、版本、非 debuggable 和正式签名证书检查。

正式版在全部自动门禁通过后发布。按照本版本的发布约束，真机覆盖安装测试在正式发布后执行；如发现问题，只以前滚方式发布 2.4.3（`versionCode=58`），不删除 2.4.2 tag，不降级覆盖。

Tag 构建会先完成正式 APK 校验并推进 installer channel，只有渠道推进成功后才公开 GitHub Release。

## 版本与固定产物

- `versionName=2.4.2`
- `versionCode=57`
- 包名：`com.gzy3894.codexfortui`
- Codex CLI：`0.144.1`
- Codex 发布归档：`codex-0.144.1-zh-aarch64-unknown-linux-musl.tar.gz`
- 归档 SHA-256：`1b643a0ac10cc316d34d538f7d5fe64a96e7dda6993b1e48fa4a9f4d225fff61`
- 二进制 SHA-256：`0cde6d6bad02855732ee0ee2867005408d169c46753d414e6a487884d49e0767`

Android 不支持普通覆盖安装降级。从 2.4.2 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移和丢失风险。
