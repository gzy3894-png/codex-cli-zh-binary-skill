# Codex for TUI 失败日志

日期：2026-07-02

本文档只记录已经暴露的事实、根因判断和后续止损要求。当前目标不是继续修补旧链路，而是避免仓库继续把失败实现包装成可用方案。

## 原始需求

用户需要的是一个很小的闭环：

1. 安装 APK 或入口脚本后，首次打开自动安装运行依赖。
2. 用户输入 `codex` 时检测本地配置是否存在。
3. 没有配置时进入 `codex 配置模式`，引导写入 API Base、API Key、默认模型。
4. 配置完成后正常进入 Codex。
5. 额外保留两个明确命令：`codex 配置模式` 和 `codex 更新`。

这个需求不应该演化成多层 bootstrap、profile、resume、preflight、模型目录刷新、脚本自更新互相覆盖的链路。

## 用户可见失败

1. 默认模型写入错误：

```toml
model = "可用模型：
gpt-5.5"
```

直接原因是模型选择函数把菜单提示文本和真实模型值混在 stdout，调用方又把 stdout 整体当成 `model` 写入 `config.toml`。

2. `codex 更新` 没有只更新必要补丁，而是再次拉取整套脚本，并出现“部分脚本更新失败”。

直接原因是更新链路按脚本文件逐个下载，缺少 manifest、版本边界、原子替换、失败回滚和清晰日志。任何单文件失败都会把用户留在半更新状态。

3. `codex 配置模式` 写入配置后，Codex 启动失败：

```text
Error loading configuration: failed to parse model_catalog_json path `/root/.codex/model_catalog.json` as JSON: unknown variant `web_search`, expected `text` or `text_and_image`
```

直接原因是生成的 `model_catalog.json` 使用了当前 Codex 不接受的枚举值：

```json
"web_search_tool_type": "web_search"
```

当前二进制只接受 `text` 或 `text_and_image`。这说明脚本生成配置时没有用真实 Codex 二进制做解析校验。

4. 多轮修复仍在同一套复杂脚本上叠加补丁，导致新问题不断出现，用户无法获得一个“安装后能用”的稳定版本。

## 底层问题

1. 没有固定配置模板。

`config.toml`、`auth.json`、`model_catalog.json` 应该由固定模板生成，变量只允许写入 API Base、API Key、默认模型等少数值。实际实现里配置由多个函数、多个状态文件和多个入口共同生成，覆盖方向不清晰。

2. 启动、配置、更新职责混在一起。

普通 `codex` 启动不应该刷新模型、不应该更新脚本、不应该重写配置。实际实现中 bootstrap、resume、local、update、profile 之间存在多条隐式路径。

3. 更新系统没有发布级约束。

`codex 更新` 应该只下载一个版本 manifest，再按版本进行原子切换。实际实现更接近“把仓库里的脚本再拉一遍”，缺少失败可恢复能力。

4. 测试没有覆盖真实失败点。

已有 smoke/static 测试没有强制校验：

- `config.toml` 中 `model` 必须是单行纯模型 ID。
- `model_catalog.json` 必须能被当前 Codex 二进制接受。
- `codex 更新` 失败时不能留下半更新文件。
- 配置模式写入后必须能立即执行 `codex --version` 或等价的配置加载检查。

5. 仓库保留了旧脚本备份，增加了误用和继续复用旧实现的风险。

`backup/legacy-scripts-20260702/` 已从仓库删除。已发布版本和 Git 历史不删除。

## 当前仓库处置

1. 已发布 GitHub Release 保留，不删除 tag，不删除 release asset。
2. 仓库中的 tracked 旧脚本备份目录 `backup/legacy-scripts-20260702/` 删除。
3. 当前 TUI 安装/更新链路不能再被描述为已验证可用。
4. 后续如继续发版，必须先按“最小闭环”重做，不在旧链路上继续堆补丁。

## 后续发版前硬性要求

1. 固定模板：仓库提供静态 `config.toml` 模板、`auth.json` 模板、`model_catalog.json` 模板；脚本只替换明确占位符。
2. 单入口：普通 `codex` 只启动 Codex；`codex 配置模式` 只配置；`codex 更新` 只更新。
3. 原子更新：下载 manifest 到临时目录，全部校验通过后一次性切换；失败必须保留旧版本。
4. 可读日志：每一步写清楚下载地址、目标文件、校验结果、失败原因。
5. CI 必须跑：
   - shell 语法检查；
   - 配置模板渲染测试；
   - `model_catalog.json` schema 兼容测试；
   - 更新失败回滚测试；
   - GitHub Actions APK debug 构建。
6. 不依赖用户真机完成基本验收。远程用户只能通过已安装版本执行 `codex 更新` 接收补丁。

## 结论

这不是用户需求复杂导致的失败，而是实现边界失控导致的失败。旧脚本链路应该停止复用；仓库需要先止血、删掉旧脚本备份、保留已发布版本，再以固定模板和少量命令重新实现。
