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
  codex-local profile-new NAME
  codex-local profile-save NAME
  codex-local profile-use NAME_OR_ID
  codex-local profile-list
  codex-local profile-show NAME_OR_ID
  codex-local profile-rename NAME_OR_ID NEW_NAME
  codex-local profile-delete NAME_OR_ID
  codex-local profile-sync NAME_OR_ID
  codex-local compact-policy [show|follow-model|fixed TOKENS]
  codex-local config-status
  codex-local rollback-v1
  codex-local repair-launcher
  codex-local run [args...]

说明:
  普通 codex 启动不会调用本脚本。
  refresh-models 是显式命令，只更新当前第三方配置的模型目录。
  profile-sync 用于把用户手改的运行配置或新登录态同步回配置档。
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
    codex_config_menu
    ;;
  refresh-models)
    codex_init_env
    codex_config_refresh_models
    ;;
  profile-new)
    shift
    [ -n "${1:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_profile_new "$1"
    ;;
  profile-save)
    shift
    [ -n "${1:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_profile_save "$1"
    ;;
  profile-use)
    shift
    [ -n "${1:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_profile_use "$1"
    ;;
  profile-list)
    codex_init_env
    codex_config_profile_list
    ;;
  profile-show)
    shift
    [ -n "${1:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_v2_prepare
    codex_config_v2_show_profile "$1"
    ;;
  profile-rename)
    shift
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_v2_prepare
    work="$(codex_config_v2_work_root)"
    codex_config_v2_run "$work/profile-rename.json" profile rename "$1" "$2"
    ;;
  profile-delete)
    shift
    [ -n "${1:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_v2_prepare
    work="$(codex_config_v2_work_root)"
    codex_config_v2_run "$work/profile-delete.json" profile delete "$1"
    ;;
  profile-sync)
    shift
    [ -n "${1:-}" ] || { usage; exit 2; }
    codex_init_env
    codex_config_v2_prepare
    work="$(codex_config_v2_work_root)"
    codex_config_v2_run "$work/profile-sync.json" profile sync-current "$1"
    ;;
  compact-policy)
    shift
    codex_init_env
    codex_config_v2_prepare
    work="$(codex_config_v2_work_root)"
    case "${1:-show}" in
      show)
        codex_config_v2_run "$work/compact-policy.json" compact-policy show
        cat "$work/compact-policy.json"
        ;;
      follow-model)
        codex_config_v2_run "$work/compact-policy.json" compact-policy follow-model
        cat "$work/compact-policy.json"
        ;;
      fixed)
        [ -n "${2:-}" ] || { usage; exit 2; }
        codex_config_v2_run "$work/compact-policy.json" compact-policy fixed "$2"
        cat "$work/compact-policy.json"
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    ;;
  config-status)
    codex_init_env
    codex_config_engine status
    ;;
  rollback-v1)
    codex_init_env
    work="$(codex_config_v2_work_root)"
    codex_config_v2_run "$work/rollback-v1.json" rollback-v1
    cat "$work/rollback-v1.json"
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
