# Codex for TUI 2.5.29

2.5.29 是第三方 Responses API 自动压缩挂死的 P0 前滚热修。

## 修复内容

Codex `0.144.1` 会把名称为 `OpenAI` 的 provider 判定为支持官方远程压缩协议。Codex for TUI 为保持 Responses API 兼容性，也会把第三方中转站显示名写为 `OpenAI`，但同时设置 `requires_openai_auth=false`。

旧能力判断只检查 provider 名称，导致第三方服务达到自动压缩阈值时误发官方专用的远程压缩请求。服务不支持该协议时会返回 `invalid_responses_request`，当前会话随后无法继续。

新版在 ARM64 musl 二进制的源码准备阶段加入 fail-closed 安全补丁：

- 只有内置且要求 OpenAI 身份验证的官方 provider 使用 OpenAI 远程压缩。
- Azure Responses provider 保持原有远程压缩路径。
- 名称为 `OpenAI`、但 `requires_openai_auth=false` 的第三方 Responses provider 改用本地压缩。
- 普通 Responses 请求、模型选择、上下文长度和 2.5.28 的 80% 自动压缩阈值保持不变。

## 已受损旧会话

本热修会在发送压缩请求前改走本地路径，防止新的线程进入同一故障链，但不会自动重建已经写入远程 compaction replacement history 的旧会话。

- 覆盖安装前不要删除或改写旧 rollout。
- 升级后的原始 P0 复测应使用新会话。
- 需要挽救的旧会话先备份 rollout，再单独做 pre-compact 历史恢复；不要把“新版能继续新会话”误报成“旧会话已自动恢复”。

## 构建门禁

- 源码补丁使用精确锚点、幂等应用；上游结构变化时直接失败，不静默生成不安全二进制。
- fixture 测试验证第三方 `OpenAI` 名称 provider 不再声明远程压缩能力。
- 源码完整性门禁验证安全条件和回归测试已进入待编译源码。
- GitHub Actions `29588836456` 在 ARM64 musl 构建后运行完整
  `codex-model-provider-info` 测试：24 passed / 0 failed / 0 filtered，并显式核对第三方负向、官方 OpenAI 与 Azure 正向三条结果。

## 升级

直接覆盖安装 2.5.29 APK 并重新打开 App：

- 不要卸载旧 App。
- 不要清除 App 数据。
- 不需要手动运行 `codex 更新` 或 `codex-local refresh-models`。
- 普通启动仍不会自动更新脚本、刷新第三方模型目录或覆盖用户手写配置。

## 版本元数据

- `versionName=2.5.29`
- `versionCode=95`
- runtime epoch：`apk-2.5.29`
- Codex binary：`0.144.1-zh.2`，包含 remote compaction safety patch
- 包名：`com.gzy3894.codexfortui`

## 回滚

Android 已安装 `versionCode=95` 后不能普通覆盖降级。若真机回归发现产品问题，应发布更高 versionCode 的前滚热修，不要求用户卸载或清除数据。
