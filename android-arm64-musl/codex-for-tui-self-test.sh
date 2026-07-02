#!/usr/bin/env sh
set -eu

pass_count=0
warn_count=0
fail_count=0

say() { printf '%s\n' "$*"; }
pass() { pass_count=$((pass_count + 1)); printf '通过: %s\n' "$*"; }
warn() { warn_count=$((warn_count + 1)); printf '警告: %s\n' "$*" >&2; }
fail() { fail_count=$((fail_count + 1)); printf '失败: %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

find_cmd() {
  command -v "$1" 2>/dev/null || true
}

expect_equal() {
  label="$1"
  actual="$2"
  expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label = $expected"
  else
    fail "$label 当前是 $actual，期望 $expected"
  fi
}

self_dir="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || printf '.')"
[ -n "${HOME:-}" ] || export HOME="/root"
expected_home="${CODEX_FOR_TUI_SELF_TEST_EXPECT_HOME:-/root}"
expected_codex_home="${CODEX_FOR_TUI_SELF_TEST_EXPECT_CODEX_HOME:-$expected_home/.codex}"
codex_home="${CODEX_HOME:-${HOME:-/root}/.codex}"

find_script_root() {
  for root in \
    "${CODEX_ZH_SCRIPT_INSTALL_ROOT:-}" \
    "$self_dir" \
    "$self_dir/../share/codex-zh/scripts" \
    "$HOME/.local/share/codex-zh/scripts" \
    "/usr/local/share/codex-zh/scripts" \
    "$HOME/.codex-for-tui/remote" \
    "$HOME/.cache/codex-zh/scripts"
  do
    [ -n "$root" ] || continue
    [ -r "$root/lib/codex-zh-common.sh" ] && [ -r "$root/codex-update.sh" ] && {
      printf '%s\n' "$root"
      return 0
    }
  done
  return 1
}

check_required_cmd() {
  name="$1"
  path="$(find_cmd "$name")"
  if [ -n "$path" ]; then
    pass "命令可用：$name -> $path"
  else
    fail "找不到命令：$name"
  fi
}

check_optional_cmd() {
  name="$1"
  path="$(find_cmd "$name")"
  if [ -n "$path" ]; then
    pass "命令可用：$name -> $path"
  else
    warn "找不到命令：$name"
  fi
}

say "Codex for TUI 自检"
say "本脚本只检查本地安装状态，不访问模型 API，也不会读取密钥内容。"
say ""

expect_equal "HOME" "${HOME:-}" "$expected_home"
expect_equal "CODEX_HOME" "$codex_home" "$expected_codex_home"

check_required_cmd codex
check_required_cmd codex-update
check_required_cmd codex-local
check_optional_cmd codex-self-test
check_optional_cmd codex-test

codex_cmd="$(find_cmd codex)"
if [ -n "$codex_cmd" ] && [ -r "$codex_cmd" ]; then
  if grep -F '配置模式' "$codex_cmd" >/dev/null 2>&1; then
    pass "codex 启动器包含配置模式入口"
  else
    fail "codex 启动器缺少配置模式入口"
  fi
  if grep -F '更新' "$codex_cmd" >/dev/null 2>&1; then
    pass "codex 启动器包含更新入口"
  else
    fail "codex 启动器缺少更新入口"
  fi
  if grep -F -- '--preflight' "$codex_cmd" >/dev/null 2>&1; then
    fail "codex 启动器仍包含旧 preflight 自动流程"
  else
    pass "codex 启动器没有旧 preflight 自动流程"
  fi
  if grep -F 'refresh-models' "$codex_cmd" >/dev/null 2>&1; then
    fail "codex 启动器仍会自动刷新模型"
  else
    pass "codex 启动器不会自动刷新模型"
  fi
  if grep -F '/sdcard/.codex' "$codex_cmd" >/dev/null 2>&1; then
    fail "codex 启动器仍引用 /sdcard/.codex"
  else
    pass "codex 启动器没有引用 /sdcard/.codex"
  fi
else
  fail "codex 启动器不可读，无法检查入口内容"
fi

codex_bin="$(find_cmd codex-zh-bin)"
if [ -n "$codex_bin" ] && [ -x "$codex_bin" ]; then
  if version_line="$("$codex_bin" --version 2>/dev/null | sed -n '1p')"; then
    [ -n "$version_line" ] || version_line="version command returned empty output"
    pass "Codex 二进制可执行：$version_line"
  else
    fail "Codex 二进制存在但无法执行：$codex_bin"
  fi
else
  fail "找不到 Codex 二进制：codex-zh-bin"
fi

if script_root="$(find_script_root 2>/dev/null)"; then
  pass "更新脚本目录可用：$script_root"
  [ -r "$script_root/codex-for-tui-self-test.sh" ] && pass "自检脚本已安装到更新目录" || warn "自检脚本不在更新目录；当前命令可能是按需下载运行"
else
  fail "找不到更新脚本目录"
fi

if [ -s "$codex_home/config.toml" ]; then
  config_file="$codex_home/config.toml"
  pass "检测到 Codex 配置文件：$config_file"
  if grep -F "可用模型" "$config_file" >/dev/null 2>&1; then
    fail "config.toml 的 model 值被菜单文字污染；请运行：codex 配置模式"
  elif grep '^[[:space:]]*model[[:space:]]*=' "$config_file" >/dev/null 2>&1; then
    pass "config.toml 默认模型字段未被菜单文字污染"
  fi
elif [ -s "$codex_home/auth.json" ]; then
  pass "检测到 Codex 登录文件：$codex_home/auth.json"
elif [ -s "$codex_home/install-state/official-login-mode" ]; then
  pass "检测到官方登录模式标记"
else
  warn "尚未检测到 Codex 配置；首次运行 codex 或 codex 配置模式 会继续引导"
fi

if [ -d "/sdcard/.codex" ]; then
  warn "设备上存在旧目录 /sdcard/.codex；当前版本不会再使用它"
fi

if have curl || have wget || have busybox; then
  pass "下载工具可用"
else
  fail "缺少 curl/wget/busybox，后续 codex 更新无法下载脚本"
fi

say ""
say "自检结果：通过 $pass_count 项，警告 $warn_count 项，失败 $fail_count 项。"
if [ "$fail_count" -gt 0 ]; then
  say "结论：未通过。请把上面的失败行发回来。"
  exit 1
fi

say "结论：通过。下一步可以运行：codex"
say "需要重新填写配置时运行：codex 配置模式"
say "以后只更新脚本时运行：codex 更新"
