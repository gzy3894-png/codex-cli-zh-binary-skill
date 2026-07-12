## Codex for TUI 2.5.9

Codex for TUI 2.5.9：修复 2.5.8 设备回归发现的 Codex 历史缺失和侧栏不可折叠问题。

- Codex rollout UUIDv7 不再被 UUIDv1–v5 正则过滤；显式 UUIDv7 resume 也可正确绑定窗口。
- 支持从 Codex `payload.message` 读取首条用户消息作为会话标题。
- 对话抽屉拆分为可折叠的 Codex 对话、Claude 对话和终端窗口三个分区，并显示各区数量。
- transcript 根目录仍是共享 `/root/.codex/sessions` 与 `/root/.claude/projects`；不修改用户 provider/中转配置。
- SQLite epoch `apk-2.5.9`；`versionCode=75`、`versionName=2.5.9`。
- 发布说明见 `docs/codex-for-tui-2.5.9-release-notes.md`。

## Codex for TUI 2.5.8

Codex for TUI 2.5.8：2.5.7 对话恢复实现的 CI 编译前滚修复。

- 修复 `SessionBinder.createSession()` 缺少显式 `return` 导致 Android Kotlin 编译失败。
- 保持 2.5.7 的 Codex/Claude UUID 对话导入、归档、PTY 幂等关闭和配置一致性修复。
- SQLite epoch `apk-2.5.8`；`versionCode=74`、`versionName=2.5.8`。
- 发布说明见 `docs/codex-for-tui-2.5.8-release-notes.md`。

## Codex for TUI 2.5.7

Codex for TUI 2.5.7：对话恢复闭环、PTY 关闭竞态修复与配置删除一致性修复。

- 侧栏新增 Codex/Claude 对话 registry：扫描已有 JSONL 历史，持久化真实 UUID，选择对话时复用窗口或新建 PTY 并恢复。
- 关闭窗口只移除窗口 registry、先解绑 TerminalView 再结束 PTY；对话保留，归档不做永久删除。
- 配置物化固定为 `common ⊕ managed ⊕ runtime-local`，control 删除的通用字段不再从旧 runtime 复活；无 active profile 的压缩策略同步写入 `index.json`。
- SQLite epoch `apk-2.5.7`；`versionCode=73`、`versionName=2.5.7`。
- 发布说明见 `docs/codex-for-tui-2.5.7-release-notes.md`。

## Codex for TUI 2.5.6

Codex for TUI 2.5.6：配置物化改为 common⊕managed 补丁合并；自动压缩策略全局固定真源。

- `materialize_profile` 不再以 `legacy-config.toml` 整包为底稿，改为 control common 剥离 managed 后补丁写入。
- `compact_policy` 仅认 `config-profiles-v2/index.json`；`compact-policy fixed 250000` 等一次改全局生效。
- Runtime relaunch 保留非 managed 本地附加键；legacy 仅迁移/备份。
- SQLite epoch `apk-2.5.6`；`versionCode=72`、`versionName=2.5.6`。
- 发布说明见 `docs/codex-for-tui-2.5.6-release-notes.md`。

## Codex for TUI 2.5.5

Codex for TUI 2.5.5：关窗「先落盘再杀 PTY」，修复 2.5.0–2.5.4 老窗口删不掉。

- `terminateSession`：先切 `currentSession`、移出 live map、`notifyTerminated` 写 registry，**最后** `finishIfRunning`。
- 根因：旧路径先杀 PTY，native 崩溃时 registry 未更新，冷恢复把侧栏窗口复活。
- 保留 2.5.4：配置共享 sessions、统一 workspace、关窗不 `clearAll`/`stopSelf`。
- SQLite epoch `apk-2.5.5`；`versionCode=71`、`versionName=2.5.5`。
- 发布说明见 `docs/codex-for-tui-2.5.5-release-notes.md`。



# Changelog

## Codex for TUI 2.5.4

Codex for TUI 2.5.4：关窗闪退前滚修复 + 配置共享会话 + 工作区路径统一。

- 关窗：`Handler.post` 延后杀 PTY；`remainingBefore` 快照；最后一窗不伪造 `main`、不 `clearAll`/`stopSelf`。
- 侧栏 sessions 快照，避免 Compose 删除竞态；闪退后不再清空窗口注册表。
- 不同配置档共享 `sessions`/`history`（软链控制 `CODEX_HOME`）；config/auth/sqlite 仍隔离。
- 交互 shell 与 `codex` launcher 统一 `CODEX_FOR_TUI_WORKSPACE`（默认 `/root/workspace`）。
- SQLite epoch `apk-2.5.4`；`versionCode=70`、`versionName=2.5.4`。
- 发布说明见 `docs/codex-for-tui-2.5.4-release-notes.md`。



## Codex for TUI 2.5.2

Codex for TUI 2.5.2：会话隔离语义修正 + 2.5.1 审查修复。

- 去掉添加会话时的 Agent 前缀手选；默认 shell，启动 claude/codex 时自动改前缀。
- 首条有效用户消息自动命名（软键盘 / 虚拟栏 / 托盘发送路径）。
- 通知栏 EXIT 清空注册表；进程死亡仍可冷恢复。
- 修复 createSession CODEX 覆盖、冷恢复旁路 main、changeSession resume 注入缺口。
- SQLite epoch `apk-2.5.2`；`versionCode=68`、`versionName=2.5.2`。
- 发布说明见 `docs/codex-for-tui-2.5.2-release-notes.md`。


## Codex for TUI 2.5.1

Codex for TUI 2.5.1 是 2.5.0 启动闪退热修：`SessionNaming` 非法 Unicode 属性正则在 Android ICU 上于类加载阶段崩溃。

- 根因：`SessionNaming` 类初始化编译了非法 Unicode 属性 Regex → `PatternSyntaxException` → `ExceptionInInitializerError`。
- 修复：用 `isLetterOrDigit` 清洗标题；`onSessionCreated` 加 `runCatching` 兜底；静态门禁禁止再写旧 `nonLabel = Regex` 路径。
- 会话隔离功能保留。SQLite epoch `apk-2.5.1`；`versionCode=67`、`versionName=2.5.1`。
- 发布说明见 `docs/codex-for-tui-2.5.1-release-notes.md`。

## Codex for TUI 2.5.0

Codex for TUI 2.5.0 在 2.4.10 之上交付 **会话隔离 P0**：终端标签显示名、固定 agent 前缀（codex/claude/shell）、注册表冷启动恢复、按 **UUID**（非显示名）绑定的 resume 注入。独立模块 `com.rk.terminal.session`，不改 MkSession / 全局 `CODEX_HOME`，不破坏 2.4.2+ 升级路径与 2.4.10 shell 交接。

- 抽屉与顶栏展示 `codex-…` / `claude-…` / `shell-…`；内部 id 仍为 `main` / `mainN`。
- 新建会话可选 agent 前缀；长按重命名只改后缀，前缀锁定；改名不影响 resume。
- 冷启动按 `filesDir/session-isolation/registry.json` 重建标签；有 UUID 才注入 `codex resume` / `claude --resume`，无 UUID 不瞎 resume。
- 虚拟键输入栏首条消息可自动命名；软键盘直打与 per-session `CODEX_HOME` 未做。
- SQLite build key 使用 `apk-2.5.0` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=66`、`versionName=2.5.0`；发布说明见 `docs/codex-for-tui-2.5.0-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.5.0（`versionCode=66`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.10

Codex for TUI 2.4.10 是 2.4.9 的引导交接热修：引导文字输出完后自动进入可输入 shell，不再需要 Ctrl+C；并消除启动时 `^[[…R` 类光标应答杂音。

- 根因：`init-host` 把 guest stderr 重定向到**按行** proot 噪声过滤器；busybox ash 的 PS1 无换行，过滤器永久卡住，会话停在「正在进入交互 shell…」。
- 修复：`enter_interactive_shell` 在 exec ash 前把 stderr 重新绑回会话 PTY（`exec 2>&1`）；proot 过滤器改为字节/前缀感知，立即放行 prompt 与 CSI。
- SQLite build key 使用 `apk-2.4.10` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=65`、`versionName=2.4.10`；发布说明见 `docs/codex-for-tui-2.4.10-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.10（`versionCode=65`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.9

Codex for TUI 2.4.9 是 2.4.8 的前滚体感热修：消除打开空白与引导后卡顿。

- 启动立刻打印「正在启动… / 环境已就绪，正在初始化…」，避免首次打开长时间空白。
- `MkSession` / `UpdateManager` 按 version stamp 跳过已同步 managed 脚本；不再每会话重写约 6.7MB 的 `rtk`。
- 引导结束后打印「正在进入交互 shell…」；收紧 `stty` 与 `ash -i` 交接。
- APK 升级成功后删除 `work/` 暂存树；自动清理脏 `profile.d` 测试 PATH 注入。
- SQLite build key 使用 `apk-2.4.9` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=64`、`versionName=2.4.9`；发布说明见 `docs/codex-for-tui-2.4.9-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.9（`versionCode=64`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。


## Codex for TUI 2.4.8

Codex for TUI 2.4.8 是 2.4.7 的前滚热修：引导结束后的纯 shell 固定落在 `$HOME`，并扩大 proot 噪声过滤。

- 交互 shell 交接前 `cd "$HOME"`（ENV rc 再断言一次）；`CODEX_FOR_TUI_WORKSPACE` 仍只给 `codex` launcher 用。
- 过滤 proot `ptrace` / `can't set tracee registers` / `Please set PROOT_TMP_DIR` 警告，避免污染 TUI/shell。
- `PROOT_TMP_DIR` 放到 `$PREFIX/local/proot-tmp/<session>/`；App 启动只清理 `cache/tmp` 零散文件，不再整树删除。
- SQLite build key 使用 `apk-2.4.8` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=63`、`versionName=2.4.8`；发布说明见 `docs/codex-for-tui-2.4.8-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.8（`versionCode=63`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。


## Codex for TUI 2.4.7

Codex for TUI 2.4.7 是 2.4.6 的前滚体验热修：引导结束后干净进入纯 shell，文件托盘支持多选与类型编号短名。

- 就绪引导输出完毕后明确「引导结束，进入 shell」，bootstrap 退出后由 `init.sh` 交接纯交互 shell。
- 加强 `enter_interactive_shell`：`stty` 回退到 `/dev/tty`，并用 `ENV` 一次性 rc 在 ash 启动后再次启用 echo。
- 文件托盘：每项可勾选、顶部统一发送、支持全选；批量发送共用一条附加说明。
- 临时文件展示名改为 `图片N` / `视频N` / `文本N`；磁盘缓存改为 `$stamp-img|vid|txt.ext` 短路径。
- SQLite build key 使用 `apk-2.4.7` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=62`、`versionName=2.4.7`；发布说明见 `docs/codex-for-tui-2.4.7-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.7（`versionCode=62`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.6

Codex for TUI 2.4.6 是 2.4.5 的前滚体验热修：多行就绪引导，并修复 shell 输入过程中不回显。

- 就绪提示改为多行：列出 `codex` / `codex 配置模式` / `codex 官方登录` 及各自结果。
- 进入交互 shell：`stty sane` + `ash -i`，保证 PTY 本地回显与行编辑。
- 修正默认输入模式映射：默认/严格终端用 `TYPE_NULL` 即时送键；「旧版兼容」才用 VISIBLE_PASSWORD。
- SQLite build key 使用 `apk-2.4.6` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=61`、`versionName=2.4.6`；发布说明见 `docs/codex-for-tui-2.4.6-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.6（`versionCode=61`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.5

Codex for TUI 2.4.5 优化冷启动：默认 shell、减少噪声、加快日常升级检查，并写清新/老用户流程。

- 默认 `CODEX_FOR_TUI_AUTO_START=0`：安装完成后进入 shell，打印一行就绪提示；设置页可开启「启动时自动进入 Codex」。
- 过滤 proot `can't sanitize binding` 警告；工作目录改为 `/root/workspace`，减少 project-local `model_provider` 黄色提示。
- 日常冷启动：`quick_complete` 命中后立即静默退出，不再每次联网刷新模型目录。
- 配置/会话/压缩策略说明：profile 隔离不变；压缩默认 follow-model。
- SQLite build key 使用 `apk-2.4.5` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=60`、`versionName=2.4.5`；发布说明见 `docs/codex-for-tui-2.4.5-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.5（`versionCode=60`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.4

Codex for TUI 2.4.4 是 2.4.3 的前滚热修，恢复文件托盘发送时的「附加说明」对话框。

- 2.3.9 为缩短发送路径误删 `SendPreviewDialog`；后端 `sendPreviewToAi(..., userMessage)` 一直保留，但 UI 点击“发送”会硬编码空字符串，导致附言入口消失多版。
- 2.4.4 恢复文件卡片发送确认框：可填写「附加说明（可选）」，留空仍可直接发送；文本托盘输入框不受影响。
- SQLite build key 使用 `apk-2.4.4` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- Release 校验 `versionCode=59`、`versionName=2.4.4`；发布说明见 `docs/codex-for-tui-2.4.4-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.4（`versionCode=59`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.3

Codex for TUI 2.4.3 是 2.4.2 的前滚热修，修复 aarch64-musl 上 `gpt-5.6-*` 因 `tool_mode=code_mode_only` 导致工具调用全面失败的问题。

- 随包模型目录清除 `gpt-5.6-sol` / `gpt-5.6-terra` / `gpt-5.6-luna` 的 `code_mode_only`。
- 配置引擎在目录写入、重建和 runtime 物化时统一规范化 `tool_mode`，防止升级/刷新再次写回坏值。
- SQLite build key 使用 `apk-2.4.3` runtime epoch；Codex 二进制仍为固定 `0.144.1-zh.1`。
- 会话仍按 profile 隔离；历史会话未删除，需在对应配置下 `resume`。
- Release 校验 `versionCode=58`、`versionName=2.4.3`；发布说明见 `docs/codex-for-tui-2.4.3-release-notes.md`。
- Android 不能普通覆盖降级安装；从 2.4.3（`versionCode=58`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。


## Codex for TUI 2.4.2

Codex for TUI 2.4.2 将 APK 覆盖安装升级为离线、原子、可回滚的完整用户环境升级，修复 2.4.0/2.4.1 中 App、Codex 二进制、launcher、配置引擎、模型目录和 SQLite 版本漂移。

### 修复

- APK 内置并校验固定 `0.144.1-zh.1` Codex 归档、完整受管脚本和配置引擎；老用户覆盖安装并打开 App 后自动完成升级，不再要求运行 `codex 更新`、`codex-local repair-launcher`、配置模式或手工设置 `CODEX_HOME`。
- 升级器使用锁、事务日志、受管文件备份和配置恢复点；失败恢复二进制、launcher、脚本和配置，阻止 Codex 启动，并在下次打开时重试。
- 全新 rootfs 或旧环境缺少 Python 时，首次安装确认后自动安装 `python3` 再执行 APK 升级，避免 bootstrap 与升级器互相等待。
- Android 会话统一固定 `HOME=/root`、`CODEX_HOME=/root/.codex`；根配置成为活动 V2 profile，旧 V1 current 只保留为独立历史配置，不再覆盖根配置。
- V1 profile 导入新的独立 runtime，旧目录不再被发布前 launch-check 改写；V1/V2 混合状态会补迁尚未导入的 V1 profile。
- 删除 launcher 的 V1 fallback；配置引擎未返回独立 runtime 时失败关闭。
- SQLite build key 新增 `apk-2.4.2` runtime epoch；每个 profile 的配置、会话和 SQLx 数据库继续相互隔离，相同 Codex 版本和二进制也不会复用旧版数据库。
- 所有第三方模型目录使用随包 `rust-v0.144.1` 能力离线重建；`codex-auto-*` 隐藏，`/model` 直接进入完整普通模型页。
- `gpt-5.6-sol` 恢复 `372000` 上下文、默认 `low` 和 `low/medium/high/xhigh/max/ultra` 六档推理强度；不支持的旧推理值回落到上游默认并记录报告。
- 根 sessions/history 迁入活动 profile 独立 runtime；SQLite、FIFO、软链接和插件临时对象不复制。
- 旧 `220000` 压缩阈值迁移为跟随模型；其他固定值按 profile 保留。
- 核心升级完成后只对当前第三方站点尽力刷新一次模型 ID，联网失败不阻塞离线升级结果。

### 验证与发布

- 新增 2.3.11 V1、2.4.0 中断/污染、2.4.1 故障现场、正常 V2、缺失二进制、损坏载荷、损坏状态、回滚和双终端并发升级矩阵。
- 增加完成标记前的 V1 回滚、遗留空锁回收、旧 runtime 会话软链接拆分和 V1/V2 混合补迁门禁。
- 新增真实 Codex PTY 门禁，确认 `/model` 首层直接显示普通模型页，且 `gpt-5.6-sol` 提供 `max` / `ultra`；CI 通过 QEMU 对固定 ARM64 归档重复验证。
- Debug/Release APK 构建前必须生成并校验离线载荷；构建后检查 APK 内 manifest、归档和二进制 SHA。Release 继续校验包名、`versionCode=57`、`versionName=2.4.2`、非 debuggable 和正式签名证书。
- 全部自动门禁通过后正式发布；真机覆盖测试在正式发布后执行。发现问题只前滚 2.4.3（`versionCode=58`），不删除 2.4.2 tag、不降级。
- Tag 构建先推进已验证 installer channel，成功后才公开 GitHub Release，避免 Release 与安装渠道版本不一致。
- Android 不能普通覆盖降级安装；从 2.4.2（`versionCode=57`）回到更低版本必须使用更高 versionCode 的前滚修复包，或卸载重装。

## Codex for TUI 2.4.1

Codex for TUI 2.4.1 是 2.4.0 的配置、会话隔离和模型目录热修版。

### 修复

- `codex 配置模式` 现在只负责配置：输入 `b` 返回 shell，迁移或配置失败返回非零；两种路径都不会继续进入 Codex。
- V1 迁移只备份和导入 `config.toml`、`auth.json`、模型目录与官方登录 marker，不再复制 SQLite、sessions、FIFO、插件 Git 临时对象等运行数据；旧配置运行目录保持原位。
- 每个配置使用独立 runtime home；`config.toml`、`auth.json`、模型目录、sessions、history 和 shell snapshots 不再跨配置共享。切换站点并启动第二个 Codex 时，第一个进程继续使用自己的配置和会话目录。
- 启动和退出同步使用按启动器 PID 隔离的控制文件，避免两个 Codex 同时启动或退出时互相覆盖 `status/launch/sync` 结果。
- SQLite 同时按 profile、Codex 版本和二进制 SHA 隔离，并写入运行时 `config.toml` 与 `CODEX_SQLITE_HOME`，避免旧的 `sqlite_home` 配置绕过隔离，也避免同版本不同构建复用旧 SQLx migration 数据库。
- 配置状态读取、runtime 生成或 V2 引擎解析失败时启动器改为失败关闭，不再静默退回共享 `CODEX_HOME`。
- 模型能力目录固定到 Codex `rust-v0.144.1` 的 commit 与 SHA，不再从 `openai/codex/main` 刷新；`max` / `ultra`、默认推理等级、上下文窗口和压缩阈值与当前 `0.144.1` 构建一致。
- 新生成目录和已有 profile 目录在物化时都会把所有 `codex-auto-*` 辅助模型标记为隐藏，复用 Codex `0.144.1` 原生逻辑让 `/model` 直接进入完整可选模型页；该本地规范化不联网、不刷新模型，也不修改或重新编译 Rust 二进制。

### 验证与回滚

- 本地通过 shell 语法、Python 编译、配置 V2、配置 UI、静态启动器、真实 `0.144.1` 模型目录解析和 `git diff --check` 门禁。
- 新增回归覆盖：迁移错误不启动 Codex；控制目录已有 sessions/history 时也不建立共享软链；两个不同第三方站点并行启动时 runtime/session/SQLite 相互独立；相同版本不同二进制 SHA 使用不同 SQLx 数据库。
- 2.4.1 继续复用已发布的 `0.144.1-zh.1` 中文 ARM64 musl 二进制及原 SHA；只需由 GitHub Actions 构建、签名和验证新版 APK，并在真机复测 `/model` 与跨站点并行会话。
- Android 不能普通覆盖降级安装；从 2.4.1（`versionCode=56`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.4.0

Codex for TUI 2.4.0 重构了配置档、模型目录和上下文策略底层。

### 新增

- 新增事务型 Python 配置引擎和稳定 ID 配置档，支持增删改查、激活、同步当前运行配置、同名保护和取消不写入。
- 新增 V1 无损迁移、完整迁移备份、崩溃自动恢复和 `codex-local rollback-v1`。
- 新增 Provider 模型 ID与 OpenAI Codex 官方能力目录精确合并；支持显式映射、未知模型保守模式和缓存回退。
- 新增动态 `max` / `ultra` 推理等级、真实上下文窗口、有效窗口比例和自动压缩阈值报告。
- 新增“跟随模型 / 固定 token”压缩策略，以及 `profile-show/rename/delete/sync`、`compact-policy`、`config-status` 命令。

### 修复与兼容

- 随包 Codex CLI 中文 ARM64 musl 二进制升级到 `0.144.1`；二进制、压缩包和中文模型目录均固定到独立非 Latest Release `v0.144.1-zh.1` 并校验 SHA256。
- 新版 code-mode 公共 provider/session API 在 musl stub 中保持编译兼容；因上游 `rusty_v8` 没有该目标的预编译归档，Code Mode 继续明确报告 unavailable，不伪装成可用。
- 配置模式改为扁平 CRUD，每层支持返回和退出；编辑保持原配置 ID，切换前会处理 `runtime_dirty`。
- TOML 写入保留用户注释和未知字段；API Key 不进入命令行参数或 JSON 输出。
- 普通启动不联网、不迁移、不覆盖用户配置；旧更新器只在用户显式进入配置模式时按需补齐引擎资源。
- 删除旧 shell 中固定 `272000` 上下文、固定推理等级和嵌套配置菜单的死代码。

### 验证与回滚

- 本地通过配置 V2、配置 UI、安装器、静态、真实 Codex 目录解析和 `git diff --check` 门禁；Codex CLI `0.144.1` 由 GitHub Actions 原生 ARM64 runner 构建，并通过静态链接、版本、归档、哈希、汉化和模型目录门禁；APK 仍只由 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.4.0（`versionCode=55`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.11

Codex for TUI 2.3.11 是 2.3.10 的文件托盘桥接竞态热修版。

### 修复

- `codex-preview`、`codex-panel`、`codex-browser`、`codex-session` 的桥接请求不再把工作临时 `.req.tmp` 放进 App 监听/可能被清理的 `queue/` 目录。
- 队列请求改为先在 bridge 根目录完成临时文件，再发布到 `queue/*.req` 和 legacy `request`，避免 App 处理 `clear` 时删除 `queue/` 导致 shell 端 `mv ... No such file or directory`。
- 修复 2.3.10 安装后真机 smoke 在 `codex-preview clear installed_smoke_clear` 阶段暴露的请求发布竞态。

### 验证与回滚

- 本地运行 shell 语法检查、静态门禁、ops/config/installer/dev-transfer smoke；APK 编译、签名、Release 资产和安装后真机验证通过 GitHub Actions 与 installed-device smoke 完成。
- Android 不能普通覆盖降级安装；从 2.3.11（`versionCode=54`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.10

Codex for TUI 2.3.10 是 2.3.9 的文件托盘缓存生命周期热修版。

### 修复

- App 退出重进、进程重启或覆盖安装后，会从 App 本地 refs 恢复仍有效的文件托盘图片、视频、文本和浏览器截图，避免“托盘 UI 空了但临时文件不可见残留”。
- 文件托盘“清空”、单项删除、Agent clear 和超过托盘上限的自动淘汰都会同步删除 App 本地临时副本与 refs；清空还会清理浏览器截图缓存。
- `codex-clean` 现在会扫描文件托盘 refs 与浏览器截图缓存，继续采用 scan/apply/restore 的可回滚清理模型。

### 验证与回滚

- 本地已运行 shell 语法检查、`tests/codex-for-tui-static-guards.sh` 和 `tests/codex-for-tui-ops-smoke.sh`；APK 编译、签名和真机验证通过 GitHub Actions release 流程完成。
- Android 不能普通覆盖降级安装；从 2.3.10（`versionCode=53`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.9

Codex for TUI 2.3.9 是 2.3.8 的文件托盘热修版。

### 修复

- 文件托盘文本框和文件卡片点击“发送”后，短引用会写入当前 Codex TUI 会话，并延迟触发真实 Enter，避免只停在输入框等待用户再次手动发送。
- 文件卡片发送不再弹出“发送文件/附加说明”二次对话框，点击后立即走当前会话发送链路。
- `codex-preview path <编号>`、refs、status/events 和 session fold 协议保持兼容。

### 验证与回滚

- 本地已运行 `git diff --check` 和文件托盘目标静态门禁；本机缺少 Java/adb，APK 编译、签名和真机验证通过 GitHub Actions release 流程完成。
- Android 不能普通覆盖降级安装；从 2.3.9（`versionCode=52`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.8

Codex for TUI 2.3.8 是 2.3.7 的用户时区热修版。

### 修复

- `codex-context report` / `codex 上下文监测` 在 Android 环境中优先使用 `/system/bin/date` 格式化压缩触发时间，避免 Alpine/proot 默认 UTC 导致用户侧报告时间偏移。
- 非 Android 环境仍保留普通 `date` / `date -r` 兜底，方便本地脚本验证。

### 验证与回滚

- 已在已安装 2.3.7 环境中热修验证：报告时间与 Android 系统时区一致。
- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle；APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.8（`versionCode=51`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.7

Codex for TUI 2.3.7 是基于 2.3.6 稳定基线的上下文监测小版本，只增加 hook 触发后的上下文自动检测、压缩来源记录和本会话压缩次数监测。

### 新增

- `codex-context status` 会输出给 Agent 读取的上下文检测信号；`PreCompact auto` 会标记自动压缩即将发生，便于 Agent 做准备。
- `PreCompact`、`PostCompact` 和 `SessionStart` hook 事件会维护 `~/.codex/context-state/metrics`，记录本地/远程/未知来源压缩和本会话压缩次数。
- 新增 `codex-context report` 和 `codex 上下文监测` 用户报告入口，只显示最近一次压缩的用户时区时间和当前会话已压缩次数。

### 边界

- 本版本不继承 `origin/context-monitor-v2.3.7` 废案，不读取、不扫描、不改写 session/transcript 文件。
- 计数来源仅为 Codex hook 事件；不做 token 估算，不推断未触发的压缩。

### 验证与回滚

- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle；APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.7（`versionCode=50`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.6

Codex for TUI 2.3.6 是 2.3.5 的浏览器真机复测热修版。

### 修复

- 内置浏览器重复打开当前已加载根路径 URL 时，会把 `https://example.com` 与 WebView 回调的 `https://example.com/` 规范为同一加载目标，避免 `codex-browser open` 等到 `Page load timed out`。
- 同一 URL 的后台导航、安装后 smoke 复测和日常签到脚本不再因为根路径尾部 `/` 差异误判失败。

### 验证与回滚

- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle；APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.6（`versionCode=49`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.5

Codex for TUI 2.3.5 是 2.3.4 的配置热修版。

### 修复

- 第三方 OpenAI-compatible 配置继续使用内部 provider id `custom`，但生成的 `[model_providers.custom]` 会写入 `name = "OpenAI"`，避免配置模式把兼容服务显示/协议名写成 `custom`。
- 旧配置中 `name = "custom"` 或缺失 `name` 时，可在修复配置路径中规范化为 `name = "OpenAI"`。
- 用户手写 provider 名称会被保留，例如 `name = "Krill AI"` 或单引号写法，不会被强行覆盖。

### 验证与回滚

- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle；APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.5（`versionCode=48`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.4

Codex for TUI 2.3.4 是 2.3.3 的状态字段热修版。

### 修复

- `codex-browser open` 成功后，同一个 `request_id` 的 `status/result` 不再被后续 WebView snapshot 回调覆盖成 `action=snapshot`。
- `codex-browser result <request_id>` 会保留显式动作，例如 `action=navigate`，便于 Agent 稳定判断请求结果。

### 验证与回滚

- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle；APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.4（`versionCode=47`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.3

Codex for TUI 2.3.3 是 2.3.2 的安装后真机调试热修版，重点修复浏览器导航、事件过滤和开发迁移默认导出稳定性。

### 修复

- `codex-browser open` 不再把 userscript 回调完成作为导航成功前置条件；页面主框架加载完成即可返回 `state=done`，userscript 继续异步记录，避免真机误报 `Page load timed out before userscript completion`。
- `codex-panel events files/browser`、`codex-preview events`、`codex-browser events` 按 `source/mode` 过滤，避免文件托盘和浏览器事件互串。
- `codex-dev-transfer export` 默认安全导出和 `--include-secrets` 均排除 `.codex/.tmp`，避免临时插件缓存、symlink 或 pack 文件权限导致导出失败；默认导出仍排除 auth、Cookie、WebView/db/no_backup/browser 等敏感状态。

### 验证与回滚

- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle；APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.3（`versionCode=46`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.2

Codex for TUI 2.3.2 是 2.3.1 后的安全与稳定补丁，重点收紧正式发布签名、开发迁移包和配置/启动语义，并补齐 rootfs/session 生命周期门禁。

### 加固

- Release 构建继续强制使用 `ANDROID_RELEASE_*` GitHub Secrets/离线签名输入；仓库 keystore/testkey fallback 被禁用，CI 会校验 packageName、versionCode、versionName、`debuggable=false` 和正式签名 SHA-256。
- `codex-dev-transfer` 默认不导出 `auth.json`、API key、Codex sessions、Cookie、WebView/db/no_backup/browser 等登录态；敏感迁移必须显式 `--include-secrets --yes`。
- `codex-dev-transfer import` 校验 tar 白名单，拒绝绝对路径、`..`、symlink、hardlink 和 device 节点，降低迁移包覆盖风险。

### 修复与稳定性

- 普通启动保持不自动联网更新脚本、不刷新模型目录、不覆盖用户手写配置；首次无配置仍保留初始化流程。
- 快捷授权默认回车跳过，只有明确输入 `1` 才写入 requirements/hooks；配置写入采用临时文件、原子替换和可恢复备份。
- App 生命周期补齐弱引用、每 session 独立 `PROOT_TMP_DIR` 与清理；rootfs 安装增加 lock、ready marker 和临时目录原子切换。

### 验证与回滚

- 本地只运行 shell/static/smoke 门禁，不本地构建 APK/Gradle。APK、正式签名和 Release 资产只通过 GitHub Actions 构建。
- Android 不能普通覆盖降级安装；从 2.3.2（`versionCode=45`）回到更低版本需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.1

Codex for TUI 2.3.1 是 2.3.0 后的稳定底座版本，新增 App 内置诊断/清理/运维命令，并进一步收紧发布与迁移安全门禁。

### 新增

- 新增 `codex-doctor`、`codex-clean`、`codex-ops`，用于只读诊断、可回滚清理、任务日志、断线续连提示。
- 新增 `$PREFIX/local/ops/tasks/<task_id>/` 状态目录，统一保存 `status`、`events`、`summary`、`resume_hint`。

### 加固

- files/browser/session/perf 状态补齐 `schema_version`、`timestamp_ms`、`needs_user`、`user_action` 等统一字段。
- 浏览器 session log 只写 timestamp/request/state/action/ok 摘要，避免记录 URL、token 或 cookie。
- GitHub Actions 正式 release 不再允许仓库 keystore/testkey fallback；release 签名必须来自 `ANDROID_RELEASE_*` GitHub Secrets，缺失任一 secret 必须失败。
- Release APK 上传前校验 packageName、versionCode、versionName、`debuggable=false` 和正式签名证书 SHA-256。
- `codex-dev-transfer` 后续安全迁移默认不应包含 auth、Cookie、WebView/db/no_backup/browser 等敏感登录态；需要敏感迁移时必须显式确认。

### 验证与回滚

- 本地仍只运行非 APK 门禁：`git diff --check`、各 bridge asset `sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`sh tests/codex-for-tui-ops-smoke.sh`、`sh tests/codex-for-tui-dev-transfer-smoke.sh`。
- APK、正式签名和 release 资产只通过 GitHub Actions 构建；release 缺少 GitHub Secrets、包名/版本/debuggable/签名任一不匹配都会失败。
- Android 不能普通覆盖降级安装；从 2.3.1 回到 2.3.0 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。

## Codex for TUI 2.3.0

Codex for TUI 2.3.0 是 2.2.9 后的稳定化回归版，重点不是新增大功能，而是把现有移动端协作能力纳入可重复门禁，并修复回归中发现的浏览器重复导航超时问题。

### 修复

- `codex-browser open <当前已加载 URL>` 不再等待新的页面完成回调直到超时；页面已在当前标签加载且未处于 loading 时会直接返回 `state=done`、当前 `url/title/tab_id`，需要强制刷新时继续使用 `codex-browser reload`。
- 保留 2.2.9 的后台/折叠 WebView 截图兜底链路，`screenshot --push --background` 仍必须保持 `visible=0 collapsed=1` 并生成真实页面内容。

### 稳定化

- 新增 `docs/codex-for-tui-2.3.0-regression.md`，把安装/更新/首启、配置管理器、快捷授权、文件托盘、浏览器、Custom Tabs/Auth、会话折叠和终端性能状态整理成 2.3 发布回归矩阵。
- 新增 `tests/codex-for-tui-installed-device-smoke.sh`，用于已安装真机环境内检查包版本、命令同步、RTK/context hook、文件托盘、会话折叠、终端 perf 状态、浏览器 JS/后台截图/Auth 残留等关键路径。
- `tests/codex-for-tui-browser-smoke.sh` 增加重复打开已加载 URL 的回归断言，避免后续把同类超时问题重新带回。

### 验证

- 本地仍只运行非 APK 门禁：`git diff --check`、各 bridge asset `sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`sh -n tests/codex-for-tui-device-smoke.sh`、`sh -n tests/codex-for-tui-browser-smoke.sh`、`sh -n tests/codex-for-tui-installed-device-smoke.sh`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：`CODEX_TUI_REQUIRE_HOOKS=1 CODEX_TUI_EXPECTED_VERSION_CODE=43 tests/codex-for-tui-installed-device-smoke.sh` 与 `tests/codex-for-tui-browser-smoke.sh` 必须通过；Release APK 签名证书继续等于 2.x 正式证书指纹。

## Codex for TUI 2.2.9

Codex for TUI 2.2.9 是 2.2.8 的正式热修版，继续修复后台/折叠 WebView 截图在真机上仍为空图的问题。

### 修复

- 后台截图 capture host 不再用透明宿主，而是挂到 App 内容背后，保持 WebView 处于真实窗口和可见层级中，同时不展开浏览器托盘。
- 创建 WebView 前启用 `WebView.enableSlowWholeDocumentDraw()`，截图前等待 Choreographer 渲染帧和 visual state，减少刚挂载即截图导致的空白。
- WebView 截图兜底链路改为普通 `draw()`、自定义 WebView `onDraw()`、`capturePicture()` 和 DOM 文本快照四段，避免单一路径在 Android WebView 上返回灰白图。
- 继续保留 2.2.7/2.2.8 的 JS 裸表达式、Auth 状态清理和 RTK/context hook 来源显示修复。

### 验证

- 本地仍只运行非 APK 门禁：`git diff --check`、各 bridge asset `sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`sh -n tests/codex-for-tui-device-smoke.sh`、`sh -n tests/codex-for-tui-browser-smoke.sh`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：后台截图必须在 `visible=0 collapsed=1` 时生成真实 Example Domain 页面，且不自动展开浏览器托盘。

## Codex for TUI 2.2.8

Codex for TUI 2.2.8 是 2.2.7 的正式热修版，修复 2.2.7 真机复测发现的后台/折叠 WebView 截图灰白空图问题。

### 修复

- 后台截图临时 capture host 改为窗口内 1% 透明挂载，避免 Android WebView 在屏幕外不可见宿主上跳过真实内容渲染。
- 截图前临时切换 WebView 软件层绘制；若 `draw()` 结果疑似空白，再使用 `capturePicture()` 兜底，提升 `codex-browser screenshot --push --background` 在折叠状态下截取真实网页的成功率。
- 保持 2.2.7 的其他修复：`codex-browser js "document.title"` 裸表达式返回值、Auth 取消状态清理，以及 RTK/context 系统级 requirements hook 状态识别。

### 验证

- 本地仍只运行非 APK 门禁：`git diff --check`、各 bridge asset `sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`sh -n tests/codex-for-tui-device-smoke.sh`、`sh -n tests/codex-for-tui-browser-smoke.sh`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：2.2.7 已通过的 RTK/context status、JS 裸表达式继续通过；后台截图必须在 `visible=0 collapsed=1` 时生成真实 Example Domain 页面；`auth-cancel` 后普通 `open` 不残留取消状态。

## Codex for TUI 2.2.7

Codex for TUI 2.2.7 是 2.2.6 的真机回归热修版，重点修复浏览器后台截图、JS 返回值、Auth 状态残留和 RTK/context 快捷授权状态显示。

### 修复

- `codex-browser js` 支持裸表达式返回值，`codex-browser js "document.title"` 会返回页面标题，同时兼容旧的 `return ...;` 脚本。
- 后台/折叠状态下的 WebView 截图会临时使用离屏宿主等待渲染，不再生成白图或灰图，也不会自动展开浏览器托盘。
- Auth Browser 完成/取消后的状态不再污染后续普通导航、DOM、JS 或截图请求。
- `codex-rtk status` 和 `codex-context status` 同时识别用户级 `config.toml` 与系统级 `/etc/codex/requirements.toml` 托管 hooks，并输出 `*_hook_source`。

### 验证

- 本地仍只运行非 APK 门禁：`git diff --check`、各 bridge asset `sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`sh -n tests/codex-for-tui-device-smoke.sh`、`sh -n tests/codex-for-tui-browser-smoke.sh`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：RTK/context status 显示系统托管 hook 已启用；`js "document.title"` 返回标题；后台截图是真实网页；`auth-cancel` 后普通 `open` 不残留取消状态。

## Codex for TUI 2.2.6

Codex for TUI 2.2.6 是 bridge 并发可靠性、协作浏览器状态同步和发布安全门禁修复版。

### 修复

- 浏览器请求队列按 `request_id` 幂等处理，避免 legacy `request` 与 queue `.req` 同一请求被重复执行。
- 文件托盘、会话折叠和 Agent 面板请求改为队列化处理，降低快速连续请求覆盖丢失的概率。
- 协作浏览器导航增加 token/timeout 隔离，避免旧页面回调完成新请求；外部 scheme、fallback 和下载统一进入用户确认路径。
- 浏览器状态、用户协作状态和 request 结果持续写回本地 bridge 文件，减少 `status/auth-wait` 看到旧状态。
- Android 存储边界、备份规则、FileProvider 分享范围和 release 签名/Release 上传门禁加固。
- 2.x 既有签名文件从 debug/testkey 命名位置迁移到 `app/codex-for-tui-2x-release.keystore`，release 构建直接走正式 signingConfig 并继续校验旧 2.x 证书指纹。

### 验证

- 本地仍只运行非 APK 门禁：`git diff --check`、各 bridge asset `sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`sh -n tests/codex-for-tui-device-smoke.sh`、`sh -n tests/codex-for-tui-browser-smoke.sh`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建；release 构建必须校验 version/tag、所有 APK 签名和 SHA256SUMS。
- 真机验证重点：连续 browser/preview/session/panel 请求不重复不丢失，Custom Tabs 完成/取消/折叠信号可回传，浏览器多标签/Cookie/截图和外部链接确认回归。

## Codex for TUI 2.2.5

Codex for TUI 2.2.5 是 2.2.4 发布前追加的 RTK 安全热修版：保留 RTK 绝对路径修复，同时避免把复杂 `find` 命令错误改写成 `rtk find`。

### 修复

- `codex-rtk hook` 遇到带 `-exec`、`-execdir`、`-ok`、`-delete`、`-not`、`-o`、`-a`、括号或 `!` 的复杂 `find` 命令时直接 fail-open，保留原命令执行。
- 保留 2.2.4 的绝对路径修复：RTK 改写结果中的 `rtk ...` 会转为 App 内置 RTK 二进制路径，避免 `PATH` 缺失导致 `rtk: not found`。
- 静态门禁新增复杂 `find` 不改写检查，避免后续回退。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：登录 shell 下 `git status` 等 RTK 改写命令使用绝对路径；复杂 `find ... -exec ...` 不被 RTK 改写，避免命令失败。

## Codex for TUI 2.2.4

Codex for TUI 2.2.4 是 2.2.3 的 RTK hook 热修版，重点修复少数登录 shell 环境下 `PATH` 不含 `$PREFIX/local/bin` 时，RTK 改写后的命令可能报 `rtk: not found` 的问题。

### 修复

- `codex-rtk hook` 现在会把 RTK 改写结果中的 `rtk ...` 转为当前 App 内置 RTK 二进制的绝对路径，避免依赖用户 shell 的 `PATH`。
- hook 会识别已经使用绝对路径的 RTK 命令并直接跳过，避免二次改写或循环。
- 静态门禁新增绝对路径检查，确保后续不会退回裸 `rtk ...`。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：登录 shell 下即使 `command -v rtk` 为空，RTK hook 也能返回 `$PREFIX/local/bin/rtk ...` 绝对路径，终端命令不再报 `rtk: not found`。

## Codex for TUI 2.2.3

Codex for TUI 2.2.3 是 2.2.2 的真机门禁热修版，重点修复打开 Custom Tabs/外部浏览器后 bridge 停止消费的问题。

### 修复

- 文件托盘、协作浏览器和 session fold bridge 不再在 `MainActivity.onStop()` 时停止；Activity 被 Custom Tabs/系统浏览器盖到后台时仍可消费 Agent 写入的请求。
- bridge 观察器和 fallback poll 改为 Activity 销毁时才停止，避免 Auth Browser 折叠/完成/取消、外部 scheme 协作、文件托盘和会话折叠状态卡在旧请求。
- `onResume` 继续主动轮询文件托盘、浏览器和 session fold 请求，回到终端后能尽快补处理积压事件。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：覆盖 2.2.2 高频输出门禁，并重跑 Custom Tabs/Auth Browser 返回后 bridge 继续消费、外部 scheme、文件托盘、session fold、Cookie/localStorage、截图推送和旧命令兼容。

## Codex for TUI 2.2.2

Codex for TUI 2.2.2 是终端流畅度优化版，重点减少长输出、托盘状态刷新和 bridge 轮询叠加造成的卡顿。

### 优化

- 终端输出刷新按屏幕帧合并，避免每次文本变化都立即触发 `TerminalView` 重绘。
- Compose 层不再因普通重组无条件刷新终端；托盘、浏览器和会话折叠状态尽量结构相等去重。
- 文件托盘、浏览器和 session fold bridge 优先由文件事件触发，保留低频 fallback poll，减少空轮询。
- 新增 `$PREFIX/local/perf/terminal.status` 轻量排障状态，便于确认合帧和 bridge 工作模式。
- 持久化 `/root/AGENTS.md` 子代理路由约定：复杂跨模块任务用主代理总控、`explorer` 只读探索、`worker` 分片实现。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：`seq 1 5000`、`yes | head -n 5000` 高频输出，输入/复制粘贴/软键盘/虚拟键/切 session，文件/浏览器/会话托盘，bridge 事件，以及 2.2.1 Auth Browser 回归。

## Codex for TUI 2.2.1

Codex for TUI 2.2.1 是 2.2 浏览器协作体验热修版，重点减少 Auth Browser 对用户前台页面的打断。

### 修复

- `codex-browser auth-open` 默认只创建 App 内安全登录任务卡，不再自动跳出到 Custom Tabs/系统浏览器，避免 Agent 测试或重试时反复弹外部页面。
- 需要立刻打开系统浏览器时可显式使用 `codex-browser auth-open --open-now ...`；用户也可以在任务卡里点“打开/重开”，Agent 侧仍可用 `auth-reopen <request_id>`。
- 旧 `codex-browser auth URL`、`external URL`、`custom-tab URL` 保持立即打开兼容，避免破坏已有脚本。
- 官方登录向导继续创建 Auth 任务卡并展示一次性 code；用户确认后再从卡片进入 Custom Tabs，脚本仍用 `codex login status` 验证，不打印 token/Cookie/auth.json。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 真机验证重点：`auth-open` 不自动弹外部浏览器，`auth-reopen/打开按钮` 才打开；完成/取消/折叠/重开继续写回结构化字段。

## Codex for TUI 2.2.0

Codex for TUI 2.2.0 聚焦浏览器协作：把登录/授权/验证码交给调用式 Custom Tabs Auth Browser，同时继续增强内置 WebView Agent Browser。

### 新增

- `codex-browser auth-open/auth-wait/auth-status/auth-done/auth-cancel/auth-reopen`：打开安全登录任务卡，用户完成、取消、折叠、重开都会写回 `user_action/auth_state/visible/collapsed`。
- `codex 官方登录`：调用 `codex login --device-auth`，解析登录链接和一次性验证码，通过 Custom Tabs 打开，完成后用 `codex login status` 验证。
- 外部 scheme 打开确认：`intent://`、`mailto:`、`tel:`、`baiduboxapp://` 等不再直接跳走，先让用户确认，并写回确认/取消事件。

### 增强

- WebView Agent Browser 增加验证码/风控检测字段：`risk_challenge_detected`、`risk_challenge_kind`、`recommended_next_action`。
- Auth Browser 不读取 DOM、密码、Cookie 或 `auth.json`；结果和日志只记录用户动作、链接、一次性 code 和状态，不打印 token/Cookie。
- 保持旧 `codex-browser open/status/screenshot/auth/external/user-wait` 用法兼容。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 正式发布前必须真机验证 auth-open 用户动作回传、Codex device-auth 登录向导、WebView 静默/展示、多标签事件、风控 needs_user、外部 scheme 确认、Cookie/localStorage 持久化、截图推送和旧命令兼容。

## Codex for TUI 2.1.3

Codex for TUI 2.1.3 是 2.1.2 的真机热修版，重点修复协作浏览器 userscript 自动注入在后台 WebView 场景下可能静默失败的问题。

### 修复

- `codex-browser open` 等待 userscript 注入完成；如果注入超时或执行失败，会把错误返回给终端，不再误报页面已可用。
- userscript 注入改为延迟重试，并通过 `new Function(...)` 隔离执行脚本内容，降低脚本内容破坏注入包装器的概率。
- 注入回调会解析执行结果，并写入本地 `local/browser/userscripts.log`，便于真机排查是匹配、执行还是 WebView 回调问题。
- userscript match 支持多条规则和通配符，保留裸字符串 contains 匹配兼容旧命令。
- README 修正已安装用户更新说明：覆盖 APK 不会自动联网刷新 `~/.local/share/codex-zh/scripts`；需要配置管理器脚本时请显式运行 `codex 更新 && codex-local repair-launcher`。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 覆盖安装后必须再次运行 `tests/codex-for-tui-browser-smoke.sh` 真机验证 userscript、多标签、队列、Cookie/WebStorage、截图推送和接管状态。

## Codex for TUI 2.1.2

Codex for TUI 2.1.2 把配置管理器修复合入正式版，不需要先安装 2.1.1。全新安装会拉取最新脚本；已安装用户覆盖 APK 后，如需刷新 `~/.local/share/codex-zh/scripts` 里的配置管理器脚本，仍应显式运行 `codex 更新 && codex-local repair-launcher`。

### 修复

- `codex 配置模式` 改为配置管理器，围绕配置的增、删、改、查和切换工作。
- 新建或编辑第三方 API 配置后主动询问是否保存为配置档，不再要求用户事后手动选择“保存当前配置”。
- 切换配置或退出配置模式前，如果当前配置有未保存修改，会先提示保存、另存或放弃，避免配置档为空或丢失。
- 已保存配置支持查看和删除；空列表、错误编号、取消删除等操作都会返回当前菜单，不再直接退出整个配置模式。
- 切换旧配置时会补齐 `approval_policy = "never"`、`sandbox_mode = "danger-full-access"` 和 hooks，避免授权或 RTK/context 设置丢失。

### 验证

- 新增配置菜单 smoke：自动保存新配置、切换前保存未保存修改、空列表/错误输入不退出、删除可取消。
- 本地门禁仍只运行 shell/static 测试，不运行本地 Gradle/APK 构建。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。

## Codex for TUI 2.1.1

Codex for TUI 2.1.1 是 2.1.0 协作浏览器硬化后的热修版，重点修复真机 smoke 中发现的队列竞态、桥接轮询退出和 userscript 注入抢跑问题。

### 修复

- `codex-browser` 写请求时先准备 legacy request，再暴露队列文件，避免 App 抢先消费队列后 shell 侧复制失败。
- 浏览器桥轮询加入顶层异常保护和单队列文件异常隔离，单个坏请求不会让后台桥接协程停止消费后续请求。
- 页面 `onPageFinished` 后等待 userscript 注入回调再完成 `open` 请求；`get-text #selector` 对短暂异步渲染/注入增加小轮询。

### 验证

- 本地仍只运行非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- APK、正式签名和 release 资产仍只通过 GitHub Actions 构建。
- 覆盖安装后需再次运行 `tests/codex-for-tui-browser-smoke.sh` 真机验证多标签、队列、Cookie/WebStorage、截图推送、userscript 和接管状态。

## Codex for TUI 2.1.0

Codex for TUI 2.1.0 硬化协作浏览器，并加入终端默认背景图，让 WebView 自动化更接近长期可用。

### 新功能

- `codex-browser` 改为队列请求，避免并发命令覆盖同一个 request 文件；每个请求写入独立 `results/<request_id>.status/json`。
- 浏览器补齐多标签列表、选择/关闭、历史记录、Cookie 状态/验证、Cookie flush、WebView 自绘截图推送文件托盘。
- 新增本地 userscript 注入：从本地文件导入，按 URL match 注入，不自动下载远程脚本。
- 内置终端预设背景图，默认透明度为 1；用户自定义背景仍然优先。

### 边界

- 内嵌 WebView 的 Cookie/WebStorage 会持久化，但不与 Chrome、Edge 或 Custom Tabs 共享。
- `cookies status|verify` 只返回 Cookie 名称和数量，不输出 Cookie value。
- Chrome/Edge 原生扩展不适用于 Android WebView；本版本以 userscript 作为可控替代。

### 验证

- 本地非 APK 门禁：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`。
- 新增 `tests/codex-for-tui-browser-smoke.sh`，用于真机测试多标签、请求队列、Cookie、localStorage、历史、截图推送、userscript 和用户接管状态。
- APK、签名校验、RTK 二进制和 release 资产仍只通过 GitHub Actions 构建。

## Codex for TUI 2.0.8

Codex for TUI 2.0.8 修复 RTK 默认启用、会话托盘耗时刷新和上下文压缩监测三类问题，让长会话在自动 compact 前后更容易交接。

### 新功能

- 新增 `codex-context status|events|hook|enable|disable|verify`，默认配置 `PreCompact`、`PostCompact` 和 `SessionStart(startup|resume|compact)` hook。
- `codex-context` 会把自动/手动 compact 事件写入 `~/.codex/context-state/`，并追加到 App 会话事件流，后续 Agent 可用 `codex-context events` 或 `codex-session events` 追踪。

### 修复

- 配置模式默认写入 `hooks = true`，并保持 Codex for TUI 托管的 RTK/context hook；新建、编辑或切换第三方配置后不再丢失 RTK。
- 会话托盘运行中耗时改为 UI ticker 自动刷新，不再依赖 Agent 主动传参，也不会每秒写状态文件。

### 验证与回滚

- 本地非 APK 门禁要求：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`、RTK/context hook 样例输入测试。
- APK、签名校验、RTK 二进制和 release 资产仍只通过 GitHub Actions 构建。
- 完整源码由 tag `codex-for-tui-v2.0.8` 固定保存；本轮实施前回滚锚点为 `rollback/2.0.7-before-2.0.8-5cac3a8` 和 `rollback-2.0.7-before-2.0.8`。

## Codex for TUI 2.0.7

Codex for TUI 2.0.7 内置 RTK，并补齐会话托盘总折叠能力，重点减少之后 shell 输出刷屏，同时让 Agent 能明确感知会话时间线是否折叠。

### 新功能

- 内置 RTK `v0.43.0`，由 GitHub Actions 构建 `aarch64-unknown-linux-musl` 二进制并随 APK 同步到终端环境。
- 新增 `codex-rtk status|enable|disable|verify|hook`，可显式检查 RTK、启用/关闭 Codex PreToolUse hook，并保留 `RTK_DISABLED=1` 临时跳过。
- `codex-rtk enable` 只追加 Codex for TUI 管理的 hook 块，并会备份 `~/.codex/config.toml`；`disable` 只移除托管块，不删除用户自己的 hooks 或配置。
- 会话时间线新增总折叠：`codex-session timeline collapse|expand|toggle [REASON]`。
- `codex-session status/events/result` 新增 `timeline_collapsed=0|1`，用户点击折叠/展开会写入 `user_timeline_collapsed` / `user_timeline_expanded`，Agent 命令会写入 `agent_timeline_collapsed` / `agent_timeline_expanded`。

### 体验优化

- 会话时间线 header 更紧凑，显示会话摘要和 `runs/items` 数量。
- 总折叠只隐藏列表，不清空 run/item 记录；清空仍是独立操作。
- RTK 只压缩之后进入 Codex 的 shell 输出，不会删除已经存在的终端文本或历史上下文。

### 验证

- 本地非 APK 门禁通过：`sh -n`、`sh tests/codex-for-tui-static-guards.sh`、`sh tests/codex-for-tui-installer-smoke.sh`、`git diff --check`、RTK hook 样例输入和配置保留测试。
- GitHub Actions 分支构建通过：脚本静态检查、RTK ARM64 musl 构建、qemu 验证和 test APK。
- 正式 APK、签名校验和 release 资产仍只通过 GitHub Actions tag/release 构建。

### 回滚

- 完整源码由 tag `codex-for-tui-v2.0.7` 固定保存，GitHub Release 会自动保留 source zip/tar。
- 回滚到 2.0.6 可安装 release `codex-for-tui-v2.0.6` 的 APK，源码 tag 为 `codex-for-tui-v2.0.6`。
- 本轮功能基线保留在分支 `rollback/rtk-session-fold-base-65f7c28`。

## Codex for TUI 2.0.6

Codex for TUI 2.0.6 新增会话折叠 v1，让 Agent 过程信息进入 App 原生结构化时间线，而不是完整刷进终端文本。

### 新功能

- 新增 `codex-session` 桥接命令，支持 `start/add/done/fail/expand/collapse/remove/clear/status/events/wait/result`。
- 新增会话折叠时间线：思考、工具、文本、文件、浏览器和最终结果可归入同一个 run，完成后默认折叠为“已处理 <耗时>”。
- 用户展开、折叠、删除和清空会话折叠项会写入 `session-fold/events`，Agent 可以通过 `codex-session events/wait` 感知。
- 文件托盘、长文本发送和浏览器协作会在存在 active session run 时附加到当前折叠记录；旧 `codex-preview`、`codex-browser`、`codex-panel` 用法保持兼容。

### 验证

- 本地非 APK 构建门禁：静态 guards、APK asset shell 语法和 `git diff --check`。
- APK 构建、签名校验和 release 资产仍只通过 GitHub Actions 完成。

## Codex for TUI 2.0.5

Codex for TUI 2.0.5 修复 2.0.4 安装后运行时调试发现的 Agent 面板协议字段一致性问题。

### 修复

- 文件托盘后台加入图片、视频或文本时，`codex-panel status files` 会立即带上 `item_id`、`name`、`stamp`，不必等到 `present` 后才能拿到编号。
- 文件删除后的 `result` 不再把被删除项继续写成 `active_item`，避免 Agent 误判当前仍选中旧文件。
- 浏览器 `status` 和 `result` 补齐 `active_item`、`tab_id`、`tabs_count`、`visible`、`collapsed` 等字段，和统一事件流保持一致。
- 显式 `present` / `user-wait` 会在处理请求前先标记浏览器面板展开，避免 `browser_needs_user` 事件先出现一条错误的 `visible=0`。

### 验证

- 本地非 APK 构建门禁：静态 guards、APK asset shell 语法、脚本库 `sh -n` 和 `git diff --check`。
- APK 构建、签名校验和 release 资产仍只通过 GitHub Actions 完成。

## Codex for TUI 2.0.4

Codex for TUI 2.0.4 完整化 Agent 面板双向协议，让文件托盘和协作浏览器都能被 Agent 稳定控制，也能把用户操作结构化回传给终端侧。

### 新功能

- 新增统一 `codex-panel` 命令：支持 `status/events/wait/result`，以及对 `files`、`browser` 的 `present`、`collapse`、`toggle`、`done`、`cancel`、`clear/close`、`select/remove` 等操作。
- `codex-preview` 兼容新增 `present`、`collapse`、`toggle`、`done`、`cancel`、`result`、`select/remove`，继续保留图片、视频、文本推送和短编号路径解析。
- `codex-browser` 兼容新增 `collapse`、`toggle`、`done/cancel`、`result`，浏览器托盘折叠和用户协作完成都能被 Agent 明确感知。
- 用户侧动作会写入统一事件字段：`visible`、`collapsed`、`request_id`、`item_id`、`active_item`、`reason`，并附带文件类型、路径、浏览器 URL、标题、标签数、是否等待用户等参数。

### 修复

- 浏览器标签选择/关闭改为通过 `MainActivity` 回写事件，不再由 UI 直接调用底层会话方法后让 Agent 猜状态。
- 文件预览打开、关闭、长按分享、系统文件选择器打开/取消/失败、用户发送文件/长文本都会同步写入事件流。
- 文本文件继续归入 `files` 面板源，用 `kind=text` 区分，避免出现 `codex-panel status files|browser` 之外的第三种面板源。
- 更新脚本生成的桥接 wrapper 包含 `codex-panel`，减少 resume/旧 PATH 环境下命令不可见的问题。

### 验证

- 本地非 APK 构建门禁：APK asset shell 语法、`codex-panel` 请求写入、文件/浏览器桥接静态 guards 和 `git diff --check`。
- APK 构建、签名校验和 release 资产仍只通过 GitHub Actions 完成。

## Codex for TUI 2.0.2

Codex for TUI 2.0.2 修复正式包自测中发现的桥接命令入口和浏览器协作状态问题。

### 修复

- 新增 `codex-preview`、`codex-push-image`、`codex-push-media`、`codex-browser` 的安装目录包装入口；即使当前 Codex 会话没有继承 App 的 `$PREFIX/local/bin`，Agent 和用户也能直接调用裸命令。
- `codex` 启动器会在运行时识别 App 桥接命令目录，并把它加入 PATH，减少 resume/旧会话环境下的命令不可见问题。
- `codex-browser user-done` 和 `user-cancelled` 现在会同步收起浏览器托盘并写入面板事件，避免 Agent 只能看到 `needs_user=0` 却无法判断托盘是否已经结束接管。

### 验证

- 本地非构建门禁：APK asset shell 语法、静态 guards 和脚本语法检查。
- 已在正式包数据目录中手动验证裸 `codex-browser`、`codex-preview`、图片/视频/文本托盘、浏览器静默打开、展示和关闭信号。
- APK 仍只通过 GitHub Actions 构建发布。

## Codex for TUI 2.0.1

Codex for TUI 2.0.1 修复 2.0 正式版后续测试中发现的浏览器和文件托盘协作问题。

### 修复

- `codex-browser open` 继续默认后台打开；当手机终端误把 `codex-browser status` 粘在同一行时，不再直接 usage 失败，而是继续发送打开请求并提示 `status` 需要另起一行执行。
- 浏览器协作命令支持 `user-wait` 和 `wait-user` 两种写法，便于 Agent 和用户按自然语序调用。
- 文件托盘发送文本/文件到当前会话时，终端提示进一步缩短为编号和 `codex-preview path <编号>`，避免长提示词干扰 shell 或 Codex 上下文。
- README 和 Android README 的浏览器测试命令改为 URL 加引号、`status` 单独执行，更适合手机终端复制粘贴。

### 验证

- 本地非构建门禁：APK asset shell 语法、安装器 smoke test、静态 guards 和 `git diff --check`。
- GitHub Actions：测试 APK 由仓库工作流构建通过；正式 APK 由 release/tag 工作流构建。
- 2.x 正式 APK 签名证书 SHA-256 固定为 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`；后续 release 构建会校验该指纹，避免误换签名导致用户无法覆盖升级。

## Codex for TUI 2.0.0

Codex for TUI 2.0.0 聚焦移动端协作体验：文件托盘、协作浏览器和更轻的顶部容器。

### 新功能

- 新增文件托盘：支持在终端中用 `codex-preview <path>` 推送图片、视频和文本到顶部容器，也支持 `--background` 后台加入托盘。
- 文件托盘第一格常驻文本框，用户发送长文本后保存为文本引用并清空输入框。
- 支持用户从 Android 系统文件管理器添加文件，并在文件卡片里预览、删除或发送到当前 Codex 会话。
- 文件发送支持附加说明，适合把截图、视频、长文本和一句用户描述一起交给 AI。
- 终端文件提示改为短编号和 `codex-preview path <编号>`，避免刷出完整应用私有路径。
- 新增协作浏览器托盘：`codex-browser open` 默认后台加载，`present` / `user-wait`（兼容 `wait-user`）才展示给用户；支持页面打开、DOM 读取、点击、输入、执行 JS、截图和用户接管。
- 新增统一面板信号：`status/events/wait` 可回传折叠、完成、取消、删除、清空、发送等用户事件。
- 浏览器支持多标签底层能力，并在托盘顶部显示紧凑标签条，可切换和关闭标签。
- WebView 文件上传会调用系统文件选择器；登录、授权、验证码和风控场景可切到 Custom Tabs 或系统浏览器处理。

### 体验优化

- 顶部“文件”和“浏览器”入口按钮进一步缩小，减少占用标题栏空间。
- 文件托盘和浏览器托盘背景透明度降低，终端上下文更容易保留在视野里。
- 文件托盘不会自启动展开，清空/删除会同步清理内部引用。
- 长文本文件只进入托盘和引用，不再把完整内容刷到终端屏幕。
- 浏览器和文件托盘不再因为后台操作自动弹出，减少 Agent 自动化时对用户终端的遮挡。

### 验证

- 本地脚本门禁：安装器 smoke test、静态 guards、设备 smoke 脚本语法、APK asset shell 语法和 `git diff --check`。
- GitHub Actions 构建：正式 APK 由仓库工作流构建。
- Android emulator smoke：覆盖浏览器桥接、用户接管、文件托盘缩略图、发送说明、短文件引用和系统文件选择器。
