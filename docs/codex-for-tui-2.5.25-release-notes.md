# Codex for TUI 2.5.25

2.5.25 在 2.5.24 之上补齐 **flag on 时自动常驻 watch**（Runtime Emitter 产品路径），默认仍 **不改变** 折叠行为。

## 相对 2.5.24 的变更

### 1) ensure-watch / stop-watch

- `codex-tui-fold-bridge ensure-watch`：仅当 `session-fold-bridge.policy` 为 `enabled=1` 时后台启动 `watch`；`enabled=0` 时 no-op 并停掉旧 daemon。
- `stop-watch`：停止后台 watch。
- `status` 增加 `watch.running` / `pid` / log 路径。

### 2) launcher 自动挂钩

- `codex` 交互启动（`codex_for_tui_run_real`）best-effort 调用 `ensure-watch`。
- 默认 policy `enabled=0` → **不启 daemon**（≡ 2.5.23 / 2.5.24 flag-off）。
- 可用 `CODEX_TUI_FOLD_BRIDGE_AUTO_WATCH=0` 完全关闭挂钩。

### 3) 仍继承 2.5.24

- fold-bridge map/tail/discover/watch + 库内包装
- 文件托盘文本可选中/复制/分享（`MediaPreviewPane`）
- flag 默认 `enabled=0` / `mode=dry-run`

### 明确未完成

- T-DELIVER 长 final 强制入托盘 + T-S1 终端摘要分流
- 默认仍 **不** 开 PTY tap

## 版本元数据

- `versionName=2.5.25`
- `versionCode=91`
- runtime epoch：`apk-2.5.25`
- 包名：`com.gzy3894.codexfortui`

## test 开启（测完务必关）

```sh
cat > "$PREFIX/local/ops/session-fold-bridge.policy" <<'EOF'
enabled=1
mode=apply
title_prefix=turn
EOF
# 下次 `codex` 交互启动会 ensure-watch；也可手动：
codex-tui-fold-bridge ensure-watch
# 回滚
cat > "$PREFIX/local/ops/session-fold-bridge.policy" <<'EOF'
enabled=0
mode=dry-run
EOF
codex-tui-fold-bridge stop-watch
```

## 回滚

1. flag：`enabled=0` / `mode=dry-run` + `stop-watch`
2. 卸 2.5.25，重装 2.5.23（`versionCode=89`）或 2.5.24（`versionCode=90`）

## 验证建议

```sh
sh tests/codex-for-tui-fold-bridge-smoke.sh
sh tests/codex-for-tui-static-guards.sh

CODEX_TUI_EXPECTED_VERSION_CODE=91 \
CODEX_TUI_EXPECTED_VERSION_NAME=2.5.25 \
  sh tests/codex-for-tui-installed-device-smoke.sh
# flag on：单 turn 后 session-fold 出现 start…done（无需模型调 codex-session）
# flag off：无自动 fold
# 托盘文本可复制
```
