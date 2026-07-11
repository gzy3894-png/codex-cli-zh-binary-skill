# Codex for TUI 2.5.0 发布说明

Codex for TUI 2.5.0 在 2.4.10 之上交付 **会话隔离 P0**：独立模块管理终端标签的显示名、固定 agent 前缀、注册表冷启动恢复，以及按 **UUID**（非显示名）绑定的 resume 命令。同时要求 **旧环境不破坏**：2.4.2 起的覆盖安装 / 自动升级路径、shell-first、浏览器/文件托盘/session-fold、配置 V2 与 2.4.10 引导回 shell 行为保持。

## 用户可见变化

1. **会话列表显示名**  
   抽屉与顶栏展示 `codex-…` / `claude-…` / `shell-…`，不再只显示裸 `main1`。内部 session id 仍为 `main` / `mainN`，兼容现有服务逻辑。

2. **新建会话可选 agent 前缀**  
   添加会话对话框可选 `codex` / `claude` / `shell`；名称始终带固定前缀。

3. **长按重命名**  
   可改后缀；前缀锁定。改名 **不影响** resume（resume 只认 `agentResumeId` UUID）。

4. **冷启动恢复标签列表**  
   进程被杀后再次打开：按注册表重建终端标签与当前选中项。  
   **不**恢复 PTY 滚动缓冲；有 UUID 时才会注入 `codex resume <uuid>` / `claude --resume <uuid>`。无 UUID 时不瞎 `resume --last`。

5. **首条消息默认命名（部分路径）**  
   经虚拟键输入栏提交的首条非空内容可用于自动命名；软键盘直打终端的自动命名为后续迭代。

## 架构要点（兼容）

- 新模块包名：`com.rk.terminal.session`（`SessionIsolation` / `SessionRegistryStore` / `SessionNaming` / `AgentKind`）。
- 持久化：`filesDir/session-isolation/registry.json`。
- 挂接为薄调用：`App`、`SessionService`、`TerminalDrawer`、`TerminalViewLayout` 等；**不改变** `MkSession` 环境变量与 proot 路径，**不改** 全局 `CODEX_HOME=/root/.codex`。
- `SessionIsolation.enabled=false` 可整模块旁路（调试用）。
- **未做** per-session `CODEX_HOME`（CLI 级硬隔离留待后续版本）。

## 旧环境 / 升级路径（不破坏）

### 从 2.4.10（或更早，含 2.4.2）覆盖安装

1. 安装 2.5.0（`versionCode=66`）并打开 App。  
2. 首次启动仍走既有 APK 离线升级（二进制 / launcher / 脚本 / 配置 V2 / 模型目录 / SQLite epoch）。  
3. 引导结束后仍应自动出现 shell prompt（2.4.10 行为保留）。  
4. 既有 Codex/Claude 配置与会话历史不因本版本被清空。  
5. 会话抽屉若曾为 `main1`/`main2`：升级后首次使用会建立新注册表元数据；旧标签进程本身不跨版本「复活」。

### 回归底线（安装后 smoke）

- installed-device 全套 smoke 通过（browser / panel / preview / session-fold / doctor 路径）。  
- 冷启动仍进 shell，无需 Ctrl+C。  
- 无会话隔离注册表时，行为接近 2.4.10（默认创建 `main` 会话）。

## 版本信息

- `versionName=2.5.0`
- `versionCode=66`
- runtime epoch：`apk-2.5.0`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.5.0 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。

## 已知限制（本版本明确不做）

- 不自动从 CLI 输出解析并绑定 resume UUID（需后续自动绑定或调试 API）。  
- 不恢复终端 transcript 全文。  
- 不做 per-session `CODEX_HOME`。  
- 软键盘直打终端的「首条消息命名」未全覆盖。
