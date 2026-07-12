# shellcheck shell=sh
[ "${CODEX_ZH_LOCAL_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_LOCAL_LOADED=1

codex_local_install_alpine_deps() {
  [ "${CODEX_ZH_SKIP_DEPS:-0}" = "1" ] && { codex_info "跳过依赖安装：CODEX_ZH_SKIP_DEPS=1"; return 0; }
  codex_have apk || { codex_warn "当前环境没有 apk，跳过 Alpine 依赖安装"; return 0; }
  profile="${CODEX_ZH_DEPS_PROFILE:-full}"
  codex_info "安装 Alpine 依赖：$profile"
  if [ "$profile" = "minimal" ]; then
    apk add --no-cache ca-certificates curl wget tar gzip git openssh-client ripgrep fd jq python3
  else
    apk add --no-cache \
      ca-certificates curl wget tar gzip unzip xz \
      git openssh-client ripgrep fd jq \
      python3 py3-pip nodejs npm \
      coreutils findutils sed grep gawk diffutils patch \
      bash make gcc g++ musl-dev pkgconf cmake ninja \
      openssl openssl-dev libffi-dev perl procps \
      bubblewrap 2>/dev/null || apk add --no-cache \
      ca-certificates curl wget tar gzip unzip xz git openssh-client ripgrep fd jq python3 py3-pip nodejs npm
  fi
  if ! codex_have bubblewrap && codex_have bwrap; then
    ln -sf "$(command -v bwrap)" /usr/local/bin/bubblewrap 2>/dev/null || true
  fi
}

codex_local_install_termux_deps() {
  [ "${CODEX_ZH_SKIP_DEPS:-0}" = "1" ] && { codex_info "跳过依赖安装：CODEX_ZH_SKIP_DEPS=1"; return 0; }
  [ -n "${PREFIX:-}" ] || codex_die "请在 Termux 环境运行"
  [ "$(id -u 2>/dev/null || printf 1)" != "0" ] || codex_die "不要在 Termux 的 su/root shell 里运行"
  codex_have apt-get || codex_die "缺少 apt-get/pkg"
  profile="${CODEX_ZH_DEPS_PROFILE:-full}"
  codex_info "安装 Termux 依赖：$profile"
  DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold update
  if [ "$profile" = "minimal" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold install -y ca-certificates curl wget tar gzip git openssh ripgrep jq python
  else
    DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold install -y \
      ca-certificates curl wget tar gzip unzip xz-utils \
      git openssh ripgrep fd jq \
      python nodejs npm \
      coreutils findutils sed grep gawk diffutils patch \
      bash make clang binutils lld pkg-config cmake ninja \
      openssl libffi perl procps proot
  fi
}

codex_local_extract_binary_from_archive() {
  archive="$1"
  out_bin="$2"
  work="$(codex_state_root)/extract-binary"
  rm -rf "$work"
  mkdir -p "$work"
  tar -xzf "$archive" -C "$work"
  src=""
  for candidate in \
    "$work/codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}" \
    "$work/codex" \
    "$work/codex-zh-bin"
  do
    [ -f "$candidate" ] && { src="$candidate"; break; }
  done
  if [ -z "$src" ]; then
    src="$(find "$work" -type f -perm -u+x -name 'codex*' 2>/dev/null | sed -n '1p')"
  fi
  [ -n "$src" ] || codex_die "压缩包中没有找到 Codex 二进制"
  codex_verify_sha256 "$src" "$CODEX_ZH_BIN_SHA256"
  mkdir -p "$(dirname "$out_bin")"
  cp "$src" "$out_bin"
  chmod 755 "$out_bin"
  rm -rf "$work"
}

codex_local_install_binary() {
  install_dir="$(codex_install_dir)"
  real_bin="$(codex_real_bin_path)"
  mkdir -p "$install_dir"
  if [ -x "$real_bin" ] && [ "$(codex_sha256_file "$real_bin" 2>/dev/null || true)" = "$(printf '%s' "$CODEX_ZH_BIN_SHA256" | codex_upper)" ]; then
    codex_info "Codex 二进制已存在并通过校验：$real_bin"
    return 0
  fi
  cache="$(codex_cache_root)"
  mkdir -p "$cache"
  archive="$cache/$CODEX_ZH_ARCHIVE"
  archive_url="${CODEX_ZH_ARCHIVE_URL:-$CODEX_ZH_BINARY_BASE_URL/$CODEX_ZH_ARCHIVE}"
  codex_download_archive "$archive_url" "$archive" "$CODEX_ZH_ARCHIVE_SHA256"
  codex_local_extract_binary_from_archive "$archive" "$real_bin"
}

codex_local_write_launcher() {
  install_dir="$(codex_install_dir)"
  real_bin="${CODEX_ZH_LAUNCHER_REAL_BIN:-$(codex_real_bin_path)}"
  build_bin="${CODEX_ZH_LAUNCHER_BUILD_BIN:-$real_bin}"
  launcher="$(codex_launcher_path)"
  mkdir -p "$install_dir"
  [ -x "$build_bin" ] || codex_die "缺少 Codex 二进制：$build_bin"
  real_q="$(codex_shell_quote "$real_bin")"
  {
    printf '%s\n' '#!/usr/bin/env sh'
    printf 'real_bin=%s\n' "$real_q"
    cat <<'EOF'
export HOME="${HOME:-/root}"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

codex_for_tui_prefix_bin() {
  if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX%/}/local/bin" ]; then
    printf '%s\n' "${PREFIX%/}/local/bin"
    return 0
  fi

  if [ -n "${PKG:-}" ]; then
    for prefix in "/data/user/0/$PKG" "/data/data/$PKG"; do
      [ -d "$prefix/local/bin" ] && { printf '%s\n' "$prefix/local/bin"; return 0; }
    done
  fi

  return 1
}

if prefix_bin="$(codex_for_tui_prefix_bin 2>/dev/null)"; then
  export PATH="$prefix_bin:$PATH"
fi

codex_for_tui_find_lib_dir() {
  for dir in \
    "${CODEX_ZH_SCRIPT_INSTALL_ROOT:-}/lib" \
    "$(dirname -- "$0")/../share/codex-zh/scripts/lib" \
    "$HOME/.local/share/codex-zh/scripts/lib" \
    "/usr/local/share/codex-zh/scripts/lib" \
    "$HOME/.cache/codex-zh/scripts/lib"
  do
    [ -r "$dir/codex-zh-common.sh" ] && { printf '%s\n' "$dir"; return 0; }
  done
  return 1
}

codex_for_tui_load_config_libs() {
  lib_dir="$(codex_for_tui_find_lib_dir)" || {
    printf '%s\n' "错误: 找不到 codex-zh 配置模块。请先运行 codex 更新。" >&2
    exit 1
  }
  # shellcheck disable=SC1090
  . "$lib_dir/codex-zh-common.sh"
  # shellcheck disable=SC1090
  . "$lib_dir/codex-zh-config.sh"
  # shellcheck disable=SC1090
  . "$lib_dir/codex-zh-local.sh"
}

codex_for_tui_has_config() {
  [ -s "$CODEX_HOME/config.toml" ] && return 0
  [ -s "$CODEX_HOME/auth.json" ] && return 0
  [ -s "$CODEX_HOME/install-state/official-login-mode" ] && return 0
  return 1
}

codex_for_tui_configure_if_missing() {
  codex_for_tui_has_config && return 0
  codex_for_tui_load_config_libs
  codex_init_env
  codex_local_configure_if_requested
}

codex_for_tui_force_configure() {
  codex_for_tui_load_config_libs
  codex_init_env
  codex_config_menu
}

codex_for_tui_binary_build_key() {
  version="$("$real_bin" --version 2>/dev/null | sed -n '1p' | cut -c1-48 | tr -c 'A-Za-z0-9._-' '_' || true)"
  [ -n "$version" ] || version="codex"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$real_bin" 2>/dev/null | awk '{print substr($1, 1, 16)}')"
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(openssl dgst -sha256 "$real_bin" 2>/dev/null | sed 's/^.*= //' | cut -c1-16)"
  else
    digest=""
  fi
  case "$digest" in
    [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
    *) return 1 ;;
  esac
  epoch="${CODEX_ZH_RUNTIME_EPOCH:-apk-2.5.12}"
  epoch="$(printf '%s' "$epoch" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-32)"
  [ -n "$epoch" ] || epoch="runtime"
  printf '%s-%s-%s\n' "$version" "$epoch" "$digest"
}

codex_for_tui_prepare_runtime() {
  control_home="$CODEX_HOME"
  runtime_home="$control_home"
  sqlite_home=""
  profile_id=""
  if ! build_key="$(codex_for_tui_binary_build_key)"; then
    printf '%s\n' "错误: 无法计算 Codex 二进制 SHA-256；未启动 Codex。" >&2
    return 1
  fi

  codex_for_tui_load_config_libs
  codex_init_env
  if engine_root="$(codex_config_engine_find_root 2>/dev/null)"; then
    CODEX_CONFIG_ENGINE_RESOLVED_ROOT="$engine_root"
    runtime_work="$control_home/install-state/config-v2-launch/$$"
    runtime_status="$runtime_work/status.json"
    mkdir -p "$runtime_work"
    if ! PYTHONNOUSERSITE=1 python3 \
      "$engine_root/libexec/codex-config-engine.py" \
      --codex-home "$control_home" status > "$runtime_status"
    then
      runtime_error="$(codex_config_v2_json_value "$runtime_status" error 2>/dev/null || true)"
      printf '%s\n' "错误: ${runtime_error:-无法读取配置状态}；未启动 Codex。" >&2
      return 1
    fi
    runtime_schema="$(codex_config_v2_json_value "$runtime_status" schema_version 2>/dev/null || true)"
    case "$runtime_schema" in
      2)
        runtime_launch="$runtime_work/launch.json"
        if PYTHONNOUSERSITE=1 python3 \
          "$engine_root/libexec/codex-config-engine.py" \
          --codex-home "$control_home" \
          profile launch --sqlite-build-key "$build_key" > "$runtime_launch"
        then
          runtime_home="$(codex_config_v2_json_value "$runtime_launch" runtime_home 2>/dev/null || true)"
          sqlite_home="$(codex_config_v2_json_value "$runtime_launch" sqlite_home 2>/dev/null || true)"
          profile_id="$(codex_config_v2_json_value "$runtime_launch" profile.id 2>/dev/null || true)"
        else
          runtime_error="$(codex_config_v2_json_value "$runtime_launch" error 2>/dev/null || true)"
          printf '%s\n' "错误: ${runtime_error:-无法准备独立配置运行目录}；未启动 Codex。" >&2
          return 1
        fi
        case "$runtime_home:$sqlite_home:$profile_id" in
          /*:/*:p-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
          *)
            printf '%s\n' "错误: 配置引擎返回了无效的独立运行目录；未启动 Codex。" >&2
            return 1
            ;;
        esac
        ;;
      1)
        printf '%s\n' "错误: 检测到旧配置结构但 APK 环境升级尚未完成；未启动 Codex。" >&2
        return 1
        ;;
      *)
        printf '%s\n' "错误: 配置引擎返回了未知结构版本；未启动 Codex。" >&2
        return 1
        ;;
    esac
  elif [ -s "$control_home/config-profiles-v2/index.json" ]; then
    printf '%s\n' "错误: 配置档 V2 引擎缺失；请先显式运行 codex-update apply，未启动 Codex。" >&2
    return 1
  fi

  [ "$runtime_home" != "$control_home" ] || {
    printf '%s\n' "错误: 配置引擎未返回独立运行目录；未启动 Codex。" >&2
    return 1
  }
  mkdir -p "$runtime_home"
  [ -n "$sqlite_home" ] || sqlite_home="$runtime_home/sqlite-builds/$build_key"
  mkdir -p "$sqlite_home"
  chmod 700 "$runtime_home" "$runtime_home/sqlite-builds" "$sqlite_home" 2>/dev/null || true

  if [ -z "$profile_id" ] && [ -n "${runtime_work:-}" ]; then
    rm -f "$runtime_work/status.json" "$runtime_work/launch.json" 2>/dev/null || true
    rmdir "$runtime_work" 2>/dev/null || true
    runtime_work=""
  fi

  export CODEX_FOR_TUI_CONTROL_HOME="$control_home"
  export CODEX_FOR_TUI_RUNTIME_HOME="$runtime_home"
  export CODEX_FOR_TUI_PROFILE_ID="$profile_id"
  export CODEX_FOR_TUI_RUNTIME_WORK="${runtime_work:-}"
  export CODEX_HOME="$runtime_home"
  export CODEX_SQLITE_HOME="$sqlite_home"
}

codex_for_tui_sync_runtime() {
  control_home="${CODEX_FOR_TUI_CONTROL_HOME:-}"
  runtime_home="${CODEX_FOR_TUI_RUNTIME_HOME:-}"
  profile_id="${CODEX_FOR_TUI_PROFILE_ID:-}"
  [ -n "$control_home" ] && [ -n "$runtime_home" ] && [ -n "$profile_id" ] || return 0
  engine_root="$(codex_config_engine_find_root 2>/dev/null || true)"
  [ -n "$engine_root" ] || return 0
  sync_work="${CODEX_FOR_TUI_RUNTIME_WORK:-$control_home/install-state/config-v2-launch/$$}"
  sync_output="$sync_work/sync-runtime.json"
  mkdir -p "$sync_work"
  if ! PYTHONNOUSERSITE=1 python3 \
    "$engine_root/libexec/codex-config-engine.py" \
    --codex-home "$control_home" \
    profile sync-runtime "$profile_id" --source-dir "$runtime_home" > "$sync_output"
  then
    sync_error="$(codex_config_v2_json_value "$sync_output" error 2>/dev/null || true)"
    printf '%s\n' "警告: ${sync_error:-运行配置同步失败；会话文件仍保留在独立运行目录。}" >&2
  fi
  rm -f "$sync_work/status.json" "$sync_work/launch.json" "$sync_output" 2>/dev/null || true
  rmdir "$sync_work" 2>/dev/null || true
}

codex_for_tui_run_real() {
  run_rc=0
  # Prefer dedicated workspace so user config under CODEX_HOME is not treated as
  # project-local config when cwd is $HOME (avoids yellow model_provider warnings).
  workspace="${CODEX_FOR_TUI_WORKSPACE:-$HOME/workspace}"
  mkdir -p "$workspace" 2>/dev/null || true
  if [ -d "$workspace" ]; then
    (cd "$workspace" && "$real_bin" "$@") || run_rc=$?
  else
    "$real_bin" "$@" || run_rc=$?
  fi
  codex_for_tui_sync_runtime
  return "$run_rc"
}

codex_for_tui_update() {
  if command -v codex-update >/dev/null 2>&1; then
    [ "$#" -gt 0 ] || set -- apply
    exec codex-update "$@"
  fi
  printf '%s\n' "错误: 找不到 codex-update。请先确认 Codex for TUI 安装完整。" >&2
  exit 1
}

codex_for_tui_context_monitor() {
  if command -v codex-context >/dev/null 2>&1; then
    subcommand="${1:-report}"
    case "$subcommand" in
      ""|报告|report)
        [ "$#" -gt 0 ] && shift
        set -- report "$@"
        ;;
      状态|status)
        [ "$#" -gt 0 ] && shift
        set -- status "$@"
        ;;
      安装|启用|enable|install)
        shift
        set -- enable "$@"
        ;;
      禁用|disable)
        shift
        set -- disable "$@"
        ;;
      日志|事件|events)
        shift
        set -- events "$@"
        ;;
      验证|verify)
        shift
        set -- verify "$@"
        ;;
    esac
    exec codex-context "$@"
  fi
  printf '%s\n' "错误: 找不到 codex-context。请先运行 codex 更新。" >&2
  exit 1
}

codex_for_tui_tty_read() {
  prompt="$1"
  default="${2:-}"
  if [ "${CODEX_ZH_FORCE_STDIN:-0}" != "1" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    [ -n "$default" ] && printf '%s [%s]: ' "$prompt" "$default" > /dev/tty || printf '%s: ' "$prompt" > /dev/tty
    IFS= read -r ans < /dev/tty || ans=""
  else
    [ -n "$default" ] && printf '%s [%s]: ' "$prompt" "$default" >&2 || printf '%s: ' "$prompt" >&2
    IFS= read -r ans || ans=""
  fi
  [ -n "$ans" ] || ans="$default"
  printf '%s' "$ans"
}

codex_for_tui_is_interactive_start() {
  case "${1:-}" in
    ""|resume|fork)
      return 0
      ;;
    --help|-h|--version|-V|help|exec|e|review|doctor|mcp|plugin|app-server|remote-control|completion|update|sandbox|debug|apply|archive|delete|unarchive|cloud|exec-server)
      return 1
      ;;
    -*)
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

codex_for_tui_offer_hook_auth() {
  [ "${CODEX_FOR_TUI_HOOK_AUTH_PROMPT:-1}" = "1" ] || return 0
  codex_for_tui_is_interactive_start "$@" || return 0
  if [ "${CODEX_ZH_FORCE_STDIN:-0}" != "1" ] && { [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; }; then
    return 0
  fi

  codex_for_tui_load_config_libs
  codex_init_env
  codex_config_managed_hooks_enabled && return 0
  codex_config_managed_hooks_available || return 0

  cat >&2 <<'EOM'
检测到 Codex for TUI 增强功能尚未快捷授权。

快捷授权会写入系统级 Codex requirements.toml，把 RTK/context 注册为 Codex for TUI 托管 hooks。
这样启动后不需要再进入 /hooks；脚本不会遍历、授权或改写其他 hook。
只有输入 1 明确同意时才会写入 requirements/hooks；直接回车会跳过本次授权。

请选择：
1. 快捷授权并启动 Codex
2. 本次跳过，直接启动
3. 退出到 shell
EOM
  while :; do
    choice="$(codex_for_tui_tty_read "请输入选项编号" "2")"
    case "$choice" in
      1)
        if ( codex_config_ensure_managed_hooks ); then
          printf '%s\n' "已完成 Codex for TUI 快捷授权。以后普通启动不会再询问。" >&2
          return 0
        fi
        printf '%s\n' "警告: 快捷授权失败：无法写入 $(codex_config_requirements_file)。本次继续普通启动。" >&2
        return 0
        ;;
      2)
        printf '%s\n' "本次跳过快捷授权。" >&2
        return 0
        ;;
      3)
        printf '%s\n' "已退出。以后运行 codex 可重新选择快捷授权。" >&2
        exit 0
        ;;
      *)
        printf '%s\n' "请输入 1、2 或 3。" >&2
        ;;
    esac
  done
}

codex_for_tui_extract_first_auth_url() {
  sed -n 's#.*\(https://[^[:space:])"]*\).*#\1#p' "$1" 2>/dev/null | sed -n '1p'
}

codex_for_tui_extract_first_device_code() {
  grep -Eo '[A-Z0-9]{4}(-[A-Z0-9]{4})+' "$1" 2>/dev/null | sed -n '1p'
}

codex_for_tui_device_auth_login() {
  tmp="${TMPDIR:-/tmp}/codex-device-auth.$$"
  : > "$tmp" || {
    printf '%s\n' "错误: 无法创建登录临时文件。" >&2
    return 1
  }
  printf '%s\n' "正在启动 Codex 官方设备码登录..." >&2
  "$real_bin" login --device-auth > "$tmp" 2>&1 &
  login_pid="$!"
  tail -f "$tmp" >&2 &
  tail_pid="$!"
  opened=0
  while kill -0 "$login_pid" 2>/dev/null; do
    if [ "$opened" = "0" ]; then
      url="$(codex_for_tui_extract_first_auth_url "$tmp")"
      if [ -n "$url" ] && command -v codex-browser >/dev/null 2>&1; then
        code="$(codex_for_tui_extract_first_device_code "$tmp")"
        codex-browser --no-wait auth-open --reason "Codex 官方登录" --code "$code" "$url" >/dev/null 2>&1 || true
        opened=1
      fi
    fi
    sleep 1
  done
  kill "$tail_pid" >/dev/null 2>&1 || true
  rc=0
  wait "$login_pid" || rc="$?"
  rm -f "$tmp" 2>/dev/null || true
  if [ "$rc" -eq 0 ] && "$real_bin" login status >/dev/null 2>&1; then
    printf '%s\n' "Codex 官方登录已通过状态检查。" >&2
    return 0
  fi
  printf '%s\n' "Codex 官方登录未通过状态检查，可稍后运行：codex 官方登录" >&2
  return "$rc"
}

codex_for_tui_offer_official_login() {
  [ "${CODEX_FOR_TUI_OFFICIAL_LOGIN_PROMPT:-1}" = "1" ] || return 0
  codex_for_tui_is_interactive_start "$@" || return 0
  [ -s "$CODEX_HOME/install-state/official-login-mode" ] || return 0
  "$real_bin" login status >/dev/null 2>&1 && return 0
  if [ "${CODEX_ZH_FORCE_STDIN:-0}" != "1" ] && { [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; }; then
    return 0
  fi

  cat >&2 <<'EOM'
检测到当前使用官方 Codex 登录模式，但 CLI 尚未登录。

推荐使用设备码登录：先创建安全登录任务卡，用户从卡片打开系统浏览器/Custom Tabs 完成授权，Codex CLI 负责写入本机登录状态。

请选择：
1. 设备码登录并启动 Codex
2. 本次跳过，直接启动
3. 退出到 shell
EOM
  while :; do
    choice="$(codex_for_tui_tty_read "请输入选项编号" "1")"
    case "$choice" in
      1|"")
        codex_for_tui_device_auth_login || return 0
        return 0
        ;;
      2)
        printf '%s\n' "本次跳过官方登录。" >&2
        return 0
        ;;
      3)
        printf '%s\n' "已退出。以后运行 codex 官方登录 可重新登录。" >&2
        exit 0
        ;;
      *)
        printf '%s\n' "请输入 1、2 或 3。" >&2
        ;;
    esac
  done
}

case "${1:-}" in
  官方登录|official-login|login-official)
    shift
    codex_for_tui_configure_if_missing
    codex_for_tui_prepare_runtime || exit $?
    codex_for_tui_device_auth_login
    login_rc=$?
    codex_for_tui_sync_runtime
    exit "$login_rc"
    ;;
  配置模式|configure|config)
    shift
    if codex_for_tui_force_configure; then
      exit 0
    else
      config_rc=$?
      printf '%s\n' "错误: 配置模式未完成，未启动 Codex。" >&2
      exit "$config_rc"
    fi
    ;;
  更新|update)
    shift
    codex_for_tui_update "$@"
    ;;
  上下文监测|context-monitor|monitor)
    shift
    codex_for_tui_context_monitor "$@"
    ;;
esac

codex_for_tui_configure_if_missing
codex_for_tui_prepare_runtime || exit $?
codex_for_tui_offer_hook_auth "$@"
codex_for_tui_offer_official_login "$@"
if [ "${1:-}" = "resume" ]; then
  resume_has_all=0
  for resume_arg in "$@"; do
    [ "$resume_arg" != "--all" ] || resume_has_all=1
  done
  if [ "$resume_has_all" = "0" ]; then
    shift
    set -- resume --all "$@"
  fi
fi
codex_for_tui_run_real "$@"
exit $?
EOF
  } > "$launcher"
  chmod 755 "$launcher"
  codex_install_case_variants "$install_dir" "$launcher"
  codex_install_app_bridge_wrappers
  codex_persist_path "$install_dir"
}

codex_local_copy_if_present() {
  src="$1"
  dest="$2"
  [ -r "$src" ] || return 1
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  chmod 755 "$dest" 2>/dev/null || true
}

codex_local_install_support_scripts() {
  install_dir="$(codex_install_dir)"
  dest_root="$(codex_script_install_root)"
  src_root="${CODEX_ZH_ACTIVE_SCRIPT_DIR:-}"
  cache_root="$(codex_script_cache_root)"
  mkdir -p "$dest_root" "$install_dir"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    source_file=""
    for root in "$src_root" "$cache_root"; do
      [ -n "$root" ] || continue
      if [ -r "$root/$rel" ]; then
        source_file="$root/$rel"
        break
      fi
    done
    [ -n "$source_file" ] || continue
    mkdir -p "$(dirname "$dest_root/$rel")"
    cp "$source_file" "$dest_root/$rel"
    chmod "$(codex_support_file_mode "$rel")" "$dest_root/$rel" 2>/dev/null || true
  done <<EOF
$(codex_support_file_list)
EOF

  for required in \
    lib/codex-zh-common.sh \
    lib/codex-zh-download.sh \
    lib/codex-zh-config.sh \
    lib/codex-zh-local.sh \
    lib/codex-zh-update.sh \
    codex-local-resume.sh \
    codex-update.sh
  do
    [ -s "$dest_root/$required" ] || codex_die "安装后缺少支持文件：$required"
  done

  [ -s "$dest_root/codex-local-resume.sh" ] && cp "$dest_root/codex-local-resume.sh" "$install_dir/codex-local-resume" && chmod 755 "$install_dir/codex-local-resume"
  [ -s "$dest_root/codex-local-resume.sh" ] && cp "$dest_root/codex-local-resume.sh" "$install_dir/codex-local" && chmod 755 "$install_dir/codex-local"
  [ -s "$dest_root/codex-update.sh" ] && cp "$dest_root/codex-update.sh" "$install_dir/codex-update" && chmod 755 "$install_dir/codex-update"
  [ -s "$dest_root/codex-for-tui-bootstrap.sh" ] && cp "$dest_root/codex-for-tui-bootstrap.sh" "$install_dir/codex-for-tui-bootstrap" && chmod 755 "$install_dir/codex-for-tui-bootstrap"
  [ -s "$dest_root/codex-for-tui-self-test.sh" ] && cp "$dest_root/codex-for-tui-self-test.sh" "$install_dir/codex-self-test" && chmod 755 "$install_dir/codex-self-test"
  [ -s "$dest_root/codex-for-tui-self-test.sh" ] && cp "$dest_root/codex-for-tui-self-test.sh" "$install_dir/codex-test" && chmod 755 "$install_dir/codex-test"
  codex_install_app_bridge_wrappers
}

codex_local_setup_agents() {
  # AGENTS.md is project/user-owned. Users can create it from Codex with /init.
  return 0
}

codex_local_configure_if_requested() {
  [ "${CODEX_ZH_SKIP_API_SETUP:-0}" = "1" ] && { codex_info "跳过 API 配置：CODEX_ZH_SKIP_API_SETUP=1"; return 0; }
  if codex_config_has_runtime_config && [ "${CODEX_ZH_OVERWRITE_CONFIG:-0}" != "1" ]; then
    codex_info "检测到已有 Codex 配置或官方登录模式，保留现状。"
    return 0
  fi
  if [ "${CODEX_ZH_SETUP_MODE:-}" = "official" ]; then
    codex_info "使用官方 Codex 登录入口；不写第三方 provider 配置。"
    codex_config_v2_initialize_official
    return 0
  fi
  if [ "${CODEX_ZH_SETUP_MODE:-}" = "third_party" ] || [ -n "${CODEX_ZH_API_BASE:-}" ] || [ -n "${CODEX_ZH_API_KEY:-}" ]; then
    codex_config_prompt_third_party
    return 0
  fi
  printf '%s\n' "请选择 Codex 初始化方式：" >&2
  printf '%s\n' "1. 官方登录入口：不写第三方 provider 配置" >&2
  printf '%s\n' "2. 第三方 Responses API：输入 Base URL 和 API Key，显式生成配置" >&2
  choice="$(codex_config_tty_read "请输入选项编号" "1")"
  case "$choice" in
    2) codex_config_prompt_third_party ;;
    *)
      codex_info "使用官方 Codex 登录入口；不写第三方 provider 配置。"
      codex_config_v2_initialize_official
      ;;
  esac
}

codex_local_install_reterminal() {
  codex_init_env
  codex_local_install_alpine_deps
  codex_local_install_binary
  codex_local_write_launcher
  codex_local_install_support_scripts
  codex_local_setup_agents
  codex_local_configure_if_requested
  codex_info "安装完成：$(codex_launcher_path)"
  if [ "${CODEX_ZH_SKIP_RUN:-0}" != "1" ]; then
    exec "$(codex_launcher_path)"
  fi
}

codex_local_install_native_termux() {
  codex_init_env
  codex_local_install_termux_deps
  codex_local_install_binary
  codex_local_write_launcher
  codex_local_install_support_scripts
  codex_local_setup_agents
  codex_local_configure_if_requested
  codex_info "安装完成：$(codex_launcher_path)"
  if [ "${CODEX_ZH_SKIP_RUN:-0}" != "1" ]; then
    exec "$(codex_launcher_path)"
  fi
}

codex_local_proot_exec() {
  rootfs="$1"
  shift
  proot -0 --link2symlink -r "$rootfs" \
    -b /dev -b /proc -b /sys \
    -b "$HOME:/termux-home" \
    -w /root /usr/bin/env -i HOME=/root PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin "$@"
}

codex_local_materialize_script_tree() {
  out_root="$1"
  src_root="${CODEX_ZH_ACTIVE_SCRIPT_DIR:-}"
  mkdir -p "$out_root"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -n "$src_root" ] && [ -r "$src_root/$rel" ]; then
      mkdir -p "$(dirname "$out_root/$rel")"
      cp "$src_root/$rel" "$out_root/$rel"
    else
      codex_download_first_script "$rel" "$out_root/$rel" ""
    fi
    chmod "$(codex_support_file_mode "$rel")" "$out_root/$rel" 2>/dev/null || true
  done <<EOF
$(codex_support_file_list)
EOF
}

codex_local_copy_tree() {
  src_root="$1"
  dest_root="$2"
  rm -rf "$dest_root"
  mkdir -p "$dest_root"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -r "$src_root/$rel" ] || codex_die "缺少脚本文件：$src_root/$rel"
    mkdir -p "$(dirname "$dest_root/$rel")"
    cp "$src_root/$rel" "$dest_root/$rel"
    chmod "$(codex_support_file_mode "$rel")" "$dest_root/$rel" 2>/dev/null || true
  done <<EOF
$(codex_support_file_list)
EOF
}

codex_local_run_rootfs_installer() {
  rootfs="$1"
  script_path="/root/codex-zh-scripts/install-reterminal-alpine.sh"
  codex_local_proot_exec "$rootfs" \
    CODEX_ZH_VERSION="$CODEX_ZH_VERSION" \
    CODEX_ZH_TARGET="$CODEX_ZH_TARGET" \
    CODEX_ZH_BRANCH="$CODEX_ZH_BRANCH" \
    CODEX_ZH_REPO_RAW="$CODEX_ZH_REPO_RAW" \
    CODEX_ZH_SCRIPT_BASE_URL="$CODEX_ZH_SCRIPT_BASE_URL" \
    CODEX_ZH_SCRIPT_RELEASE_BASE_URL="$CODEX_ZH_SCRIPT_RELEASE_BASE_URL" \
    CODEX_ZH_BINARY_BASE_URL="$CODEX_ZH_BINARY_BASE_URL" \
    CODEX_ZH_ARCHIVE_SHA256="$CODEX_ZH_ARCHIVE_SHA256" \
    CODEX_ZH_BIN_SHA256="$CODEX_ZH_BIN_SHA256" \
    CODEX_ZH_PROVIDER_ID="$CODEX_ZH_PROVIDER_ID" \
    CODEX_ZH_INSTALL_NAME="$CODEX_ZH_INSTALL_NAME" \
    CODEX_ZH_DEPS_PROFILE="${CODEX_ZH_DEPS_PROFILE:-full}" \
    CODEX_ZH_SKIP_DEPS="${CODEX_ZH_SKIP_ALPINE_DEPS:-${CODEX_ZH_SKIP_DEPS:-0}}" \
    CODEX_ZH_SKIP_API_SETUP="${CODEX_ZH_SKIP_API_SETUP:-0}" \
    CODEX_ZH_SETUP_MODE="${CODEX_ZH_SETUP_MODE:-}" \
    CODEX_ZH_API_BASE="${CODEX_ZH_API_BASE:-}" \
    CODEX_ZH_API_KEY="${CODEX_ZH_API_KEY:-}" \
    CODEX_ZH_DEFAULT_MODEL="${CODEX_ZH_DEFAULT_MODEL:-}" \
    CODEX_ZH_OVERWRITE_CONFIG="${CODEX_ZH_OVERWRITE_CONFIG:-0}" \
    CODEX_ZH_FORCE_STDIN="${CODEX_ZH_FORCE_STDIN:-0}" \
    CODEX_ZH_SKIP_RUN=1 \
    sh "$script_path"
}

codex_local_write_proot_launcher() {
  path="$1"
  rootfs="$2"
  rootfs_q="$(codex_shell_quote "$rootfs")"
  cat > "$path" <<EOF
#!/usr/bin/env sh
rootfs=$rootfs_q
exec proot -0 --link2symlink -r "\$rootfs" \\
  -b /dev -b /proc -b /sys -b "\$HOME:/termux-home" \\
  -w /root /usr/bin/env -i \\
  HOME=/root USER=root LOGNAME=root TERM="\${TERM:-xterm-256color}" \\
  PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin \\
  /root/.local/bin/codex "\$@"
EOF
  chmod 755 "$path"
}

codex_local_install_alpine_proot() {
  codex_init_env
  old_deps_profile="${CODEX_ZH_DEPS_PROFILE+x}${CODEX_ZH_DEPS_PROFILE:-}"
  CODEX_ZH_DEPS_PROFILE="${CODEX_ZH_TERMUX_DEPS_PROFILE:-minimal}"
  codex_local_install_termux_deps
  if [ -n "$old_deps_profile" ]; then
    CODEX_ZH_DEPS_PROFILE="${old_deps_profile#x}"
  else
    unset CODEX_ZH_DEPS_PROFILE
  fi
  root_base="${CODEX_ZH_ALPINE_ROOT_BASE:-${PREFIX:-$HOME}/var/lib/codex-zh/codex-alpine}"
  rootfs="$root_base/rootfs"
  cache="$(codex_cache_root)"
  alpine_version="${CODEX_ZH_ALPINE_VERSION:-3.24.1}"
  alpine_name="alpine-minirootfs-${alpine_version}-aarch64.tar.gz"
  alpine_url="${CODEX_ZH_ALPINE_URL:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/$alpine_name}"
  alpine_sha="${CODEX_ZH_ALPINE_SHA256:-F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259}"
  mkdir -p "$root_base" "$cache"
  if [ ! -s "$rootfs/etc/alpine-release" ]; then
    archive="$cache/$alpine_name"
    codex_download_archive "$alpine_url" "$archive" "$alpine_sha"
    rm -rf "$rootfs"
    mkdir -p "$rootfs"
    tar -xzf "$archive" -C "$rootfs"
  fi
  scripts_work="$(codex_state_root)/proot-scripts"
  codex_local_materialize_script_tree "$scripts_work"
  codex_local_copy_tree "$scripts_work" "$rootfs/root/codex-zh-scripts"
  codex_local_run_rootfs_installer "$rootfs"

  launcher_dir="${PREFIX:-$HOME/.local}/bin"
  mkdir -p "$launcher_dir"
  codex_local_write_proot_launcher "$launcher_dir/codex-alpine" "$rootfs"
  ln -sf "$launcher_dir/codex-alpine" "$launcher_dir/$CODEX_ZH_INSTALL_NAME" 2>/dev/null || true
  codex_info "Alpine proot 和 Codex 已安装：$rootfs"
  codex_info "入口：$launcher_dir/codex-alpine"
  if [ "${CODEX_ZH_SKIP_RUN:-0}" != "1" ]; then
    "$launcher_dir/codex-alpine" --version
  fi
}

codex_local_status() {
  missing=0
  [ -x "$(codex_real_bin_path)" ] || { printf '%s\n' "missing_binary"; missing=1; }
  [ -x "$(codex_launcher_path)" ] || { printf '%s\n' "missing_launcher"; missing=1; }
  if codex_config_has_runtime_config; then
    :
  else
    printf '%s\n' "missing_config_or_official_login"
  fi
  return "$missing"
}

codex_local_doctor() {
  if codex_local_status; then
    codex_info "本地安装核心文件完整。"
  else
    codex_warn "本地安装不完整；可运行 codex-local repair-launcher 或重新执行安装脚本。"
    return 1
  fi
}

codex_local_repair_launcher() {
  codex_init_env
  codex_local_write_launcher
  codex_local_install_support_scripts
  codex_info "已修复启动器：$(codex_launcher_path)"
}

codex_local_run() {
  codex_init_env
  [ -x "$(codex_launcher_path)" ] || codex_die "缺少启动器：$(codex_launcher_path)"
  exec "$(codex_launcher_path)" "$@"
}
