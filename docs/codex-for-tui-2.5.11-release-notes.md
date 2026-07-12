# Codex for TUI 2.5.11

2.5.11 是 2.5.10 的 P0 前滚热修，修复历史恢复失败及随后新窗口串绑。

## 修复

- 历史会话恢复不再把 app 私有目录中的 `init-host` 作为直接可执行文件启动；统一由 `/system/bin/sh` 读取脚本，再以位置参数传递恢复命令。
- 窗口 ID 复用时，显式身份覆盖会同步覆盖空 UUID，不再继承已失败或已关闭窗口的旧 `agentResumeId`。
- Codex、Claude、Grok 历史分区首次默认折叠；展开状态由常驻页面持有，反复打开侧栏不再全部重置。
- 保留 2.5.10 的唯一启动台、平级 Agent 窗口、确定性 Codex token 绑定和安全关窗逻辑。
- Codex、Claude、Grok transcript 仍为只读发现，不删除、不迁移历史内容。

## 回归重点

- 点击 7 月 10 日及更早的 Codex 历史会话能够进入真实内容。
- 历史恢复失败或退出后，新建第一个 Codex 会话不会绑定旧 UUID。
- 连续恢复不同 Agent 历史时，标题、Agent 类型与 UUID 一致。
- 连续关闭工作窗口不闪退，启动台始终存在且不可删除。

## 版本

- `versionName=2.5.11`
- `versionCode=77`
- runtime epoch：`apk-2.5.11`
