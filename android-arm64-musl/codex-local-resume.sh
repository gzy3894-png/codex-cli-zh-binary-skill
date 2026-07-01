#!/usr/bin/env sh
set -eu

[ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || printf '.')"

find_lib_dir() {
  for dir in \
    "$SCRIPT_DIR/lib" \
    "$SCRIPT_DIR/../share/codex-zh/scripts/lib" \
    "$HOME/.local/share/codex-zh/scripts/lib" \
    "/usr/local/share/codex-zh/scripts/lib" \
    "$HOME/.cache/codex-zh/scripts/lib"
  do
    [ -r "$dir/codex-zh-common.sh" ] && { printf '%s\n' "$dir"; return 0; }
  done
  return 1
}

LIB_DIR="$(find_lib_dir)" || {
  printf '%s\n' "错误: 找不到 codex-zh 模块。请先运行安装脚本，或显式运行 codex-update apply。" >&2
  exit 1
}

# shellcheck disable=SC1090
. "$LIB_DIR/codex-zh-common.sh"
# shellcheck disable=SC1090
. "$LIB_DIR/codex-zh-download.sh"
# shellcheck disable=SC1090
. "$LIB_DIR/codex-zh-config.sh"
# shellcheck disable=SC1090
. "$LIB_DIR/codex-zh-local.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  codex-local status
  codex-local doctor
  codex-local configure
  codex-local refresh-models
  codex-local repair-launcher
  codex-local run [args...]

说明:
  普通 codex 启动不会调用本脚本。
  refresh-models 是显式命令，只更新 model_catalog_json，不覆盖当前 model。
EOF
}

cmd="${1:-}"
case "$cmd" in
  status|--status)
    codex_init_env
    codex_local_status
    ;;
  doctor)
    codex_init_env
    codex_local_doctor
    ;;
  configure)
    codex_init_env
    codex_config_prompt_third_party
    ;;
  refresh-models)
    codex_init_env
    codex_config_refresh_models
    ;;
  repair-launcher)
    codex_local_repair_launcher
    ;;
  run)
    shift
    codex_local_run "$@"
    ;;
  ""|help|--help|-h)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
