# Codex for TUI 2.5.24

2.5.24 是 **test 通道** 能力包：会话折叠 Runtime Emitter（fold-bridge）库内 MVP + 文件托盘文本可复制。  
**默认不改变 2.5.23 的折叠/长文行为**：`session-fold-bridge` flag 默认 `enabled=0` / `mode=dry-run`。

## 本版包含

### 1) session-fold Runtime Emitter（方案 A · N3.4）

- 新增 `libexec/codex-tui-fold-bridge.py`：把 Codex rollout jsonl 的  
  `task_started` / `task_complete` / `turn_aborted` 映射为 `codex-session start|done|fail`。
- 命令：`map-file` · `tail-once` · `discover-active` · `watch` · `status` · `self-test`。
- 策略文件：`$PREFIX/local/ops/session-fold-bridge.policy`（样例见 `docs/architecture/session-fold-bridge.policy.example`）。
- 安装路径：support 清单 / bootstrap / apk-upgrade / `MkSession` managed asset `codex-tui-fold-bridge`。
- 本地门禁：`tests/codex-for-tui-fold-bridge-smoke.sh` + static `test_fold_bridge_runtime_emitter`。

**test 开启（测完务必关）：**

```sh
cat > "$PREFIX/local/ops/session-fold-bridge.policy" <<'EOF'
enabled=1
mode=apply
title_prefix=turn
EOF
# 对当前活跃 rollout 轮询（或指定路径）
codex-tui-fold-bridge watch --interval-ms 1500
# 回滚
cat > "$PREFIX/local/ops/session-fold-bridge.policy" <<'EOF'
enabled=0
mode=dry-run
EOF
```

### 2) 文件托盘文本复制修复

- `MediaPreviewPane` 文本预览：`SelectionContainer` 可选中；顶栏 **复制** / **分享**。
- 缩略图长按文本 → 复制正文（不再跳过 TEXT）。
- 复制/展示优先读磁盘全文（上限 2Mi 字符），避免卡在 12KB `textPreview` 切片。

### 3) 明确未完成（后续版本）

- 随 worker **自动**常驻 `watch`（本版需 test 手动/脚本拉起）。
- T-DELIVER 长 final 强制入托盘 + T-S1 终端摘要分流。
- 默认仍 **不** 开 PTY tap。

## 版本元数据

- `versionName=2.5.24`
- `versionCode=90`
- runtime epoch：`apk-2.5.24`
- 包名：`com.gzy3894.codexfortui`（debug/test 变体仍带 suffix）

## 回滚

1. flag：`enabled=0` / `mode=dry-run`（或删 policy）。
2. 卸 2.5.24，重装 2.5.23（`versionCode=89`）APK；Android 不支持覆盖降级时需先卸载。

## 验证建议

```sh
# 本地（发版前）
sh tests/codex-for-tui-fold-bridge-smoke.sh
sh tests/codex-for-tui-static-guards.sh

# 安装后
CODEX_TUI_EXPECTED_VERSION_CODE=90 \
CODEX_TUI_EXPECTED_VERSION_NAME=2.5.24 \
  sh tests/codex-for-tui-installed-device-smoke.sh
# 另：flag on 时单 turn 后 session-fold 出现 start…done；flag off 无自动 fold
# 托盘文本可长按选择 + 顶栏复制
```
