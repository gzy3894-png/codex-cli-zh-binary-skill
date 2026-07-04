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
  update_one_tmp_root="$(codex_state_root)/update-download"
  update_one_tmp="$update_one_tmp_root/$rel"
  update_one_dest="$dest_root/$rel"
  mkdir -p "$(dirname "$update_one_tmp")" "$(dirname "$update_one_dest")"
  if ! codex_download_first_script "$rel" "$update_one_tmp" ""; then
    rm -f "$update_one_tmp" "$update_one_tmp.part"
    codex_warn "无法下载：$rel"
    return 3
  fi
  if [ -s "$update_one_dest" ] && cmp -s "$update_one_tmp" "$update_one_dest"; then
    codex_info "未变化：$rel"
    rm -f "$update_one_tmp"
    return 0
  fi
  if [ "$check_only" = "1" ]; then
    codex_info "有更新：$rel"
    rm -f "$update_one_tmp"
    return 2
  fi
  if ! cp "$update_one_tmp" "$update_one_dest"; then
    rm -f "$update_one_tmp"
    codex_warn "无法写入：$update_one_dest"
    return 3
  fi
  case "$rel" in
    *.sh) chmod 755 "$update_one_dest" 2>/dev/null || true ;;
    *) chmod 644 "$update_one_dest" 2>/dev/null || true ;;
  esac
  codex_info "已更新：$rel"
  rm -f "$update_one_tmp"
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
  codex_install_app_bridge_wrappers
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
  update_tmp_root="$(codex_state_root)/update-download"
  update_files_root="$update_tmp_root/files"
  update_backup_root="$update_tmp_root/backup"
  update_missing_root="$update_tmp_root/missing"
  update_changed_list="$update_tmp_root/changed.txt"
  update_applied_list="$update_tmp_root/applied.txt"
  rm -rf "$update_tmp_root"
  mkdir -p "$dest_root" "$update_files_root" "$update_backup_root" "$update_missing_root"
  : > "$update_changed_list"
  : > "$update_applied_list"

  failed=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    update_file_tmp="$update_files_root/$rel"
    mkdir -p "$(dirname "$update_file_tmp")"
    if ! codex_download_first_script "$rel" "$update_file_tmp" ""; then
      rm -f "$update_file_tmp" "$update_file_tmp.part"
      codex_warn "无法下载：$rel"
      failed=1
    fi
  done <<EOF
$(codex_update_file_list)
EOF
  [ "$failed" -eq 0 ] || {
    rm -rf "$update_tmp_root"
    codex_die "部分脚本更新失败，请检查网络或仓库地址后重试。"
  }

  mkdir -p "$dest_root"
  changed=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    update_file_tmp="$update_files_root/$rel"
    update_dest="$dest_root/$rel"
    if [ -s "$update_dest" ] && cmp -s "$update_file_tmp" "$update_dest"; then
      codex_info "未变化：$rel"
      continue
    fi
    changed=1
    if [ "$check_only" = "1" ]; then
      codex_info "有更新：$rel"
      continue
    fi
    printf '%s\n' "$rel" >> "$update_changed_list"
    if [ -e "$update_dest" ]; then
      update_backup="$update_backup_root/$rel"
      mkdir -p "$(dirname "$update_backup")"
      if ! cp -p "$update_dest" "$update_backup"; then
        rm -rf "$update_tmp_root"
        codex_die "无法备份：$update_dest"
      fi
    else
      update_marker="$update_missing_root/$rel"
      mkdir -p "$(dirname "$update_marker")"
      : > "$update_marker"
    fi
  done <<EOF
$(codex_update_file_list)
EOF

  if [ "$check_only" != "1" ] && [ "$changed" -ne 0 ]; then
    apply_failed=0
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      update_file_tmp="$update_files_root/$rel"
      update_dest="$dest_root/$rel"
      update_dest_tmp="$update_dest.tmp.$$"
      mkdir -p "$(dirname "$update_dest")"
      if cp "$update_file_tmp" "$update_dest_tmp"; then
        case "$rel" in
          *.sh) chmod 755 "$update_dest_tmp" 2>/dev/null || true ;;
          *) chmod 644 "$update_dest_tmp" 2>/dev/null || true ;;
        esac
        if mv "$update_dest_tmp" "$update_dest"; then
          codex_info "已更新：$rel"
          printf '%s\n' "$rel" >> "$update_applied_list"
        else
          rm -f "$update_dest_tmp"
          codex_warn "无法写入：$update_dest"
          apply_failed=1
          break
        fi
      else
        rm -f "$update_dest_tmp"
        codex_warn "无法写入：$update_dest"
        apply_failed=1
        break
      fi
    done < "$update_changed_list"

    if [ "$apply_failed" -ne 0 ]; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        update_dest="$dest_root/$rel"
        update_backup="$update_backup_root/$rel"
        update_marker="$update_missing_root/$rel"
        if [ -e "$update_backup" ]; then
          cp -p "$update_backup" "$update_dest" 2>/dev/null || true
        elif [ -e "$update_marker" ]; then
          rm -f "$update_dest" 2>/dev/null || true
        fi
      done < "$update_applied_list"
      rm -rf "$update_tmp_root"
      codex_die "脚本更新写入失败，已尝试回滚。"
    fi
  fi

  if [ "$check_only" != "1" ]; then
    codex_update_install_command_links
  fi
  rm -rf "$update_tmp_root"
  if [ "$changed" -eq 0 ]; then
    codex_info "没有检测到脚本更新。"
  elif [ "$check_only" = "1" ]; then
    codex_info "检测到脚本更新；运行 codex-update apply 执行更新。"
  else
    codex_info "脚本更新完成。普通 codex 启动不会自动执行此操作。"
    codex_info "可运行 codex 更新 自检 检查安装状态。"
  fi
}
