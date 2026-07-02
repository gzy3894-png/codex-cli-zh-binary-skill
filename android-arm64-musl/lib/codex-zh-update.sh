# shellcheck shell=sh
[ "${CODEX_ZH_UPDATE_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_UPDATE_LOADED=1

codex_update_file_list() {
  cat <<'EOF'
codex-for-tui-bootstrap.sh
codex-for-tui-self-test.sh
codex-local-resume.sh
codex-update.sh
install-reterminal-alpine.sh
install-alpine-proot.sh
install.sh
lib/codex-zh-common.sh
lib/codex-zh-download.sh
lib/codex-zh-config.sh
lib/codex-zh-local.sh
lib/codex-zh-update.sh
EOF
}

codex_update_one_file() {
  rel="$1"
  dest_root="$2"
  check_only="$3"
  tmp_root="$(codex_state_root)/update-download"
  tmp="$tmp_root/$rel"
  dest="$dest_root/$rel"
  mkdir -p "$(dirname "$tmp")" "$(dirname "$dest")"
  if ! codex_download_first_script "$rel" "$tmp" ""; then
    rm -f "$tmp" "$tmp.part"
    codex_warn "无法下载：$rel"
    return 3
  fi
  if [ -s "$dest" ] && cmp -s "$tmp" "$dest"; then
    codex_info "未变化：$rel"
    rm -f "$tmp"
    return 0
  fi
  if [ "$check_only" = "1" ]; then
    codex_info "有更新：$rel"
    rm -f "$tmp"
    return 2
  fi
  if ! cp "$tmp" "$dest"; then
    rm -f "$tmp"
    codex_warn "无法写入：$dest"
    return 3
  fi
  case "$rel" in
    *.sh) chmod 755 "$dest" 2>/dev/null || true ;;
    *) chmod 644 "$dest" 2>/dev/null || true ;;
  esac
  codex_info "已更新：$rel"
  rm -f "$tmp"
  return 1
}

codex_update_install_command_links() {
  dest_root="$(codex_script_install_root)"
  install_dir="$(codex_install_dir)"
  mkdir -p "$install_dir"
  [ -s "$dest_root/codex-local-resume.sh" ] && cp "$dest_root/codex-local-resume.sh" "$install_dir/codex-local-resume" && chmod 755 "$install_dir/codex-local-resume"
  [ -s "$dest_root/codex-local-resume.sh" ] && cp "$dest_root/codex-local-resume.sh" "$install_dir/codex-local" && chmod 755 "$install_dir/codex-local"
  [ -s "$dest_root/codex-update.sh" ] && cp "$dest_root/codex-update.sh" "$install_dir/codex-update" && chmod 755 "$install_dir/codex-update"
  [ -s "$dest_root/codex-for-tui-bootstrap.sh" ] && cp "$dest_root/codex-for-tui-bootstrap.sh" "$install_dir/codex-for-tui-bootstrap" && chmod 755 "$install_dir/codex-for-tui-bootstrap"
  [ -s "$dest_root/codex-for-tui-self-test.sh" ] && cp "$dest_root/codex-for-tui-self-test.sh" "$install_dir/codex-self-test" && chmod 755 "$install_dir/codex-self-test"
  [ -s "$dest_root/codex-for-tui-self-test.sh" ] && cp "$dest_root/codex-for-tui-self-test.sh" "$install_dir/codex-test" && chmod 755 "$install_dir/codex-test"
}

codex_update_find_support_script() {
  rel="$1"
  for root in \
    "${CODEX_ZH_SCRIPT_INSTALL_ROOT:-}" \
    "${CODEX_ZH_ACTIVE_SCRIPT_DIR:-}" \
    "$(codex_script_install_root)" \
    "$(codex_script_cache_root)" \
    "$HOME/.codex-for-tui/remote"
  do
    [ -n "$root" ] || continue
    [ -r "$root/$rel" ] && { printf '%s\n' "$root/$rel"; return 0; }
  done
  return 1
}

codex_update_run_self_test() {
  codex_init_env
  rel="codex-for-tui-self-test.sh"
  if path="$(codex_update_find_support_script "$rel" 2>/dev/null)"; then
    exec sh "$path" "$@"
  fi
  dest_root="$(codex_script_install_root)"
  dest="$dest_root/$rel"
  mkdir -p "$dest_root"
  if codex_download_first_script "$rel" "$dest" ""; then
    chmod 755 "$dest" 2>/dev/null || true
    codex_update_install_command_links
    exec sh "$dest" "$@"
  fi
  codex_die "无法下载自检脚本。请先运行 codex 更新 后重试。"
}

codex_update_apply() {
  check_only="${1:-0}"
  codex_init_env
  dest_root="$(codex_script_install_root)"
  mkdir -p "$dest_root"
  changed=0
  failed=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    set +e
    codex_update_one_file "$rel" "$dest_root" "$check_only"
    rc=$?
    set -e
    case "$rc" in
      0) ;;
      1|2) changed=1 ;;
      *) failed=1 ;;
    esac
  done <<EOF
$(codex_update_file_list)
EOF
  [ "$failed" -eq 0 ] || codex_die "部分脚本更新失败，请检查网络或仓库地址后重试。"
  if [ "$check_only" != "1" ]; then
    codex_update_install_command_links
  fi
  if [ "$changed" -eq 0 ]; then
    codex_info "没有检测到脚本更新。"
  elif [ "$check_only" = "1" ]; then
    codex_info "检测到脚本更新；运行 codex-update apply 执行更新。"
  else
    codex_info "脚本更新完成。普通 codex 启动不会自动执行此操作。"
    codex_info "可运行 codex 更新 自检 检查安装状态。"
  fi
}
