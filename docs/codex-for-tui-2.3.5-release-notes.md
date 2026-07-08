# Codex for TUI 2.3.5 发布说明

Codex for TUI 2.3.5 是 2.3.4 的配置热修版。

## 修复

- 第三方 OpenAI-compatible 配置继续保留内部 provider id `custom`，但 provider 名称写为 `OpenAI`：

```toml
[model_providers.custom]
name = "OpenAI"
base_url = "https://api.example.com/v1"
wire_api = "responses"
requires_openai_auth = false
```

- 新建、编辑第三方配置时不再生成 `name = "custom"`。
- 旧配置中 `name = "custom"` 或缺失 `name` 时，可通过配置修复路径规范化为 `name = "OpenAI"`。
- 用户手写 provider 名称会被保留，不会覆盖成 `OpenAI`。

## 验证

- 新增配置门禁，覆盖新建配置、编辑配置、旧配置迁移、用户手写 provider name 保护和单引号 TOML 字符串保护。
- 静态门禁会阻止配置生成逻辑重新写回 `name = "custom"`。

## 回滚

- 2.3.5 使用正式包名 `com.gzy3894.codexfortui`，`versionCode=48`，继续沿用 2.x 正式 APK 签名证书 SHA-256 `a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc`。
- Android 不支持普通覆盖降级安装；从 2.3.5 回到更低 `versionCode` 需要前滚回滚包，或卸载重装并承担数据迁移/丢失风险。
