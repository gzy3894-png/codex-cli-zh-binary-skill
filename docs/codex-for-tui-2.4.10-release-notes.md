# Codex for TUI 2.4.10 发布说明

Codex for TUI 2.4.10 针对 2.4.9「引导文字输出完后卡住、不回 shell，只能 Ctrl+C 才出现 `localhost:/root#`」做热修；同时消除启动时 `^[[16;18R` 一类光标位置应答杂音。

## 现象（2.4.9）

1. 引导正常打印到「引导结束，进入 shell。」/「正在进入交互 shell…」
2. 之后黑块光标停住，**没有 prompt**
3. 用户 `Ctrl+C` 后才出现 `localhost:/root#`
4. 之后再输入 `claude` 等命令，偶发 `^[[16;18R` 杂音

**不是**引导脚本忘记 `exit`，而是 shell 已经起来，prompt 被过滤器吃掉了。

## 根因

`init-host` 为过滤 proot 噪声，把 **整条 guest stderr** 重定向进 FIFO，再用：

```sh
while IFS= read -r line; do ...; done
```

按行读取。

busybox ash 交互 prompt（`PS1`）写在 **stderr**，且 **没有尾部换行**；还会发 CSI `6n`（请求光标位置）。  
按行 `read` 永远等不到换行 → prompt 卡在过滤器里 → 终端看起来像「卡在引导」。  
`Ctrl+C` 产生中断并伴随换行/刷写，缓冲冲出，prompt 才出现；若终端/IME 随后把 CSI 应答 `^[[row;colR` 当普通输入回显，就变成可见杂音。

## 核心修复

### 1. 引导结束自动进入可输入 shell（无需 Ctrl+C / exit）

- `init.sh` 的 `enter_interactive_shell`：在 `exec ash -i` 前若 stderr 不是 tty，则 `exec 2>&1`，把 stderr 重新绑回会话 PTY。
- ENV 一次性 shell rc 同样做该绑定，确保 ash 启动后 prompt 直达终端。

### 2. proot 噪声过滤改为字节/前缀感知

- `init-host.sh` 不再使用按行 `read -r line`。
- 使用 `read -r -n 1` 字节扫描；仅当缓冲仍是已知 proot 噪声前缀时才暂扣，其它内容（含 shell prompt / CSI）立即透传。
- 完整噪声行（sanitize binding / ptrace / PROOT_TMP_DIR 提示等）仍丢弃。

### 3. 2.4.9 能力继续保留

- 启动立刻有文案（不再空白）
- managed 脚本 stamp，避免每会话重写 6.7MB `rtk`
- shell-first 默认、纯 shell 落在 `$HOME`、文件托盘多选

## 新用户 vs 老用户

### 新用户

1. 安装 2.4.10 APK。
2. 打开 App：看到启动/升级/引导文案后，**应立刻出现** `localhost:/root#`（或等价 prompt），无需任何按键。
3. 直接输入 `codex` / `claude` 即可。

### 老用户（2.4.9 → 2.4.10）

1. 覆盖安装 2.4.10（`versionCode=65`）。
2. 新开终端会话验证：引导结束后自动出 prompt。
3. 会话与配置不因本版本丢失；runtime epoch 为 `apk-2.4.10`。

## 版本信息

- `versionName=2.4.10`
- `versionCode=65`
- runtime epoch：`apk-2.4.10`
- Codex 二进制：固定 `0.144.1-zh.1`

Android 不支持普通覆盖安装降级。从 2.4.10 回到更低 `versionCode` 必须发布更高版本号的前滚修复包，或卸载重装并自行承担数据迁移风险。
