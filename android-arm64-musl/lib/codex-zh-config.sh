# shellcheck shell=sh
[ "${CODEX_ZH_CONFIG_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_CONFIG_LOADED=1

codex_config_file() {
  printf '%s/config.toml\n' "$(codex_home)"
}

codex_config_requirements_file() {
  printf '%s\n' "${CODEX_FOR_TUI_REQUIREMENTS_FILE:-/etc/codex/requirements.toml}"
}

codex_config_official_marker_file() {
  printf '%s/official-login-mode\n' "$(codex_state_root)"
}

codex_config_has_runtime_config() {
  [ -s "$(codex_config_file)" ] && return 0
  [ -s "$(codex_config_auth_file)" ] && return 0
  [ -s "$(codex_config_official_marker_file)" ] && return 0
  return 1
}

codex_config_auth_file() {
  printf '%s/auth.json\n' "$(codex_home)"
}

codex_config_model_catalog_file() {
  printf '%s/model_catalog.json\n' "$(codex_home)"
}

codex_config_engine_assets() {
  if command -v codex_config_engine_asset_list >/dev/null 2>&1; then
    codex_config_engine_asset_list
    return
  fi
  cat <<'EOF'
libexec/codex-config-engine.py
libexec/codex-session-defaults.py
libexec/codex-runtime-session-import.py
data/openai-models.json
data/openai-models-source.json
vendor/python/tomlkit/__init__.py
vendor/python/tomlkit/_compat.py
vendor/python/tomlkit/_types.py
vendor/python/tomlkit/_utils.py
vendor/python/tomlkit/api.py
vendor/python/tomlkit/container.py
vendor/python/tomlkit/exceptions.py
vendor/python/tomlkit/items.py
vendor/python/tomlkit/parser.py
vendor/python/tomlkit/source.py
vendor/python/tomlkit/toml_char.py
vendor/python/tomlkit/toml_document.py
vendor/python/tomlkit/toml_file.py
vendor/python/tomlkit-0.13.2.dist-info/LICENSE
vendor/python/tomlkit-0.13.2.dist-info/METADATA
EOF
}

codex_config_engine_root_valid() {
  engine_root="$1"
  [ -x "$engine_root/libexec/codex-config-engine.py" ] || return 1
  [ -x "$engine_root/libexec/codex-session-defaults.py" ] || return 1
  [ -s "$engine_root/data/openai-models.json" ] || return 1
  [ -s "$engine_root/vendor/python/tomlkit/__init__.py" ] || return 1
  [ -s "$engine_root/vendor/python/tomlkit/parser.py" ] || return 1
}

codex_config_engine_find_root() {
  for engine_root in \
    "${CODEX_CONFIG_ENGINE_ROOT:-}" \
    "${CODEX_ZH_ACTIVE_SCRIPT_DIR:-}" \
    "$(codex_script_install_root)" \
    "$(codex_script_cache_root)" \
    "$HOME/.codex-for-tui/remote"
  do
    [ -n "$engine_root" ] || continue
    if codex_config_engine_root_valid "$engine_root"; then
      printf '%s\n' "$engine_root"
      return 0
    fi
  done
  return 1
}

codex_config_engine_ensure() {
  codex_have python3 || codex_die "配置引擎需要 python3。请先运行 apk add python3，或重新执行完整安装。"
  if engine_root="$(codex_config_engine_find_root 2>/dev/null)"; then
    CODEX_CONFIG_ENGINE_RESOLVED_ROOT="$engine_root"
    return 0
  fi
  command -v codex_download_first_script >/dev/null 2>&1 ||
    codex_die "配置引擎资源缺失，且当前没有可用的显式更新下载器。请先运行 codex-update apply。"
  engine_root="$(codex_script_install_root)"
  codex_info "配置引擎资源缺失；本次显式配置操作将补齐资源。"
  engine_failed=0
  while IFS= read -r engine_rel; do
    [ -n "$engine_rel" ] || continue
    engine_dest="$engine_root/$engine_rel"
    if [ -s "$engine_dest" ]; then
      continue
    fi
    mkdir -p "$(dirname "$engine_dest")"
    if ! codex_download_first_script "$engine_rel" "$engine_dest" ""; then
      engine_failed=1
      break
    fi
    case "$engine_rel" in
      libexec/*.py) chmod 755 "$engine_dest" 2>/dev/null || true ;;
      *) chmod 644 "$engine_dest" 2>/dev/null || true ;;
    esac
  done <<EOF
$(codex_config_engine_assets)
EOF
  [ "$engine_failed" -eq 0 ] || codex_die "配置引擎资源下载失败；用户配置未修改。"
  codex_config_engine_root_valid "$engine_root" ||
    codex_die "配置引擎资源不完整；用户配置未修改。"
  PYTHONNOUSERSITE=1 python3 "$engine_root/libexec/codex-config-engine.py" --help >/dev/null 2>&1 ||
    codex_die "配置引擎自检失败；用户配置未修改。"
  CODEX_CONFIG_ENGINE_RESOLVED_ROOT="$engine_root"
}

codex_config_engine() {
  codex_config_engine_ensure
  PYTHONNOUSERSITE=1 python3 "$CODEX_CONFIG_ENGINE_RESOLVED_ROOT/libexec/codex-config-engine.py" \
    --codex-home "$(codex_home)" "$@"
}

codex_config_backup_stamp() {
  codex_backup_stamp="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf '%s' "$$")"
  CODEX_ZH_CONFIG_BACKUP_SEQ=$(( ${CODEX_ZH_CONFIG_BACKUP_SEQ:-0} + 1 ))
  printf '%s-%s-%s\n' "$codex_backup_stamp" "$$" "$CODEX_ZH_CONFIG_BACKUP_SEQ"
}

codex_config_safe_backup_name() {
  codex_backup_name="${1:-backup}"
  codex_backup_base="$(basename "$codex_backup_name" 2>/dev/null || printf '%s' "$codex_backup_name")"
  codex_backup_safe="$(printf '%s' "$codex_backup_base" | sed 's/[^A-Za-z0-9._-]/_/g')"
  [ -n "$codex_backup_safe" ] || codex_backup_safe="backup"
  printf '%s\n' "$codex_backup_safe"
}

codex_config_backup_file() {
  codex_backup_path="$1"
  codex_backup_label="${2:-$codex_backup_path}"
  [ -e "$codex_backup_path" ] || return 0
  codex_backup_dir="$(codex_state_root)/backups/$(codex_config_backup_stamp)"
  codex_backup_safe="$(codex_config_safe_backup_name "$codex_backup_label")"
  mkdir -p "$codex_backup_dir" || return 1
  if [ -d "$codex_backup_path" ]; then
    cp -pR "$codex_backup_path" "$codex_backup_dir/$codex_backup_safe"
  else
    cp -p "$codex_backup_path" "$codex_backup_dir/$codex_backup_safe"
  fi
}

codex_config_tmp_path() {
  codex_tmp_dest="$1"
  codex_tmp_dir="$(dirname "$codex_tmp_dest")"
  codex_tmp_base="$(basename "$codex_tmp_dest")"
  printf '%s/.%s.tmp.%s\n' "$codex_tmp_dir" "$codex_tmp_base" "$$"
}

codex_config_atomic_install_file() {
  codex_atomic_tmp="$1"
  codex_atomic_dest="$2"
  codex_atomic_mode="${3:-}"
  codex_atomic_dir="$(dirname "$codex_atomic_dest")"
  mkdir -p "$codex_atomic_dir" || { rm -f "$codex_atomic_tmp" 2>/dev/null || true; return 1; }
  if [ -e "$codex_atomic_dest" ]; then
    codex_config_backup_file "$codex_atomic_dest" "$codex_atomic_dest" || { rm -f "$codex_atomic_tmp" 2>/dev/null || true; return 1; }
  fi
  mv "$codex_atomic_tmp" "$codex_atomic_dest" || { rm -f "$codex_atomic_tmp" 2>/dev/null || true; return 1; }
  [ -z "$codex_atomic_mode" ] || chmod "$codex_atomic_mode" "$codex_atomic_dest" 2>/dev/null || true
}

codex_config_atomic_remove_file() {
  codex_atomic_remove_dest="$1"
  [ -e "$codex_atomic_remove_dest" ] || return 0
  codex_config_backup_file "$codex_atomic_remove_dest" "$codex_atomic_remove_dest" || return 1
  rm -f "$codex_atomic_remove_dest"
}

codex_config_atomic_replace_dir() {
  codex_atomic_tmp_dir="$1"
  codex_atomic_dest_dir="$2"
  codex_atomic_label="${3:-$codex_atomic_dest_dir}"
  codex_atomic_parent="$(dirname "$codex_atomic_dest_dir")"
  codex_atomic_old_dir="$codex_atomic_parent/.old-$(basename "$codex_atomic_dest_dir").$$"
  mkdir -p "$codex_atomic_parent" || { rm -rf "$codex_atomic_tmp_dir" 2>/dev/null || true; return 1; }
  if [ -e "$codex_atomic_dest_dir" ]; then
    codex_config_backup_file "$codex_atomic_dest_dir" "$codex_atomic_label" || { rm -rf "$codex_atomic_tmp_dir" 2>/dev/null || true; return 1; }
    rm -rf "$codex_atomic_old_dir" 2>/dev/null || true
    mv "$codex_atomic_dest_dir" "$codex_atomic_old_dir" || { rm -rf "$codex_atomic_tmp_dir" 2>/dev/null || true; return 1; }
    if mv "$codex_atomic_tmp_dir" "$codex_atomic_dest_dir"; then
      rm -rf "$codex_atomic_old_dir" 2>/dev/null || true
    else
      mv "$codex_atomic_old_dir" "$codex_atomic_dest_dir" 2>/dev/null || true
      rm -rf "$codex_atomic_tmp_dir" 2>/dev/null || true
      return 1
    fi
  else
    mv "$codex_atomic_tmp_dir" "$codex_atomic_dest_dir" || { rm -rf "$codex_atomic_tmp_dir" 2>/dev/null || true; return 1; }
  fi
}

codex_config_normalize_api_base() {
  printf '%s' "$1" | sed 's/[[:space:]]//g; s#/*$##' | awk '
    /\/v1$/ { print; next }
    { print $0 "/v1" }
  '
}

codex_config_valid_api_base() {
  cleaned="$(printf '%s' "$1" | sed 's/[[:space:]]//g')"
  case "$cleaned" in
    http://?*|https://?*) ;;
    *) return 1 ;;
  esac
  case "$cleaned" in
    *@*|*\?*|*\#*) return 1 ;;
  esac
  host_path="$(printf '%s' "$cleaned" | sed 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##')"
  host="$(printf '%s' "$host_path" | sed 's#[/?#].*##')"
  [ -n "$host" ]
}

codex_config_read_auth_key() {
  file="${1:-$(codex_config_auth_file)}"
  [ -s "$file" ] || return 1
  sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | sed -n '1p'
}

codex_config_fetch_models() {
  api_base="$1"
  api_key="$2"
  out_json="$3"
  err_file="$4"
  if codex_have curl; then
    curl -fsS --http1.1 \
      --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 60 \
      -H "Authorization: Bearer $api_key" \
      -H "Accept: application/json" \
      "$api_base/models" \
      -o "$out_json" \
      2>"$err_file"
  elif codex_have wget; then
    wget -O "$out_json" \
      --header="Authorization: Bearer $api_key" \
      --header="Accept: application/json" \
      "$api_base/models" \
      2>"$err_file"
  else
    printf '%s\n' "缺少 curl/wget，无法请求 /models" > "$err_file"
    return 1
  fi
}

codex_config_root_string_value() {
  key="$1"
  cfg="${2:-$(codex_config_file)}"
  [ -r "$cfg" ] || return 0
  awk -v key="$key" '
function is_section(line) {
  return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*($|#)/
}
function emit_if_match(line, trimmed, rest) {
  trimmed = line
  sub(/^[[:space:]]*/, "", trimmed)
  if (index(trimmed, key) != 1) {
    return
  }
  rest = substr(trimmed, length(key) + 1)
  if (rest !~ /^[[:space:]]*=/) {
    return
  }
  sub(/^[^=]*=[[:space:]]*/, "", trimmed)
  if (trimmed ~ /^"/) {
    sub(/^"/, "", trimmed)
    sub(/".*$/, "", trimmed)
    print trimmed
    exit
  }
  if (trimmed ~ /^\047/) {
    sub(/^\047/, "", trimmed)
    sub(/\047.*$/, "", trimmed)
    print trimmed
    exit
  }
}
is_section($0) { exit }
{ emit_if_match($0) }
' "$cfg" 2>/dev/null | sed -n '1p'
}

codex_config_section_string_value() {
  cfg="$1"
  section_wanted="$2"
  key="$3"
  [ -r "$cfg" ] || return 0
  awk -v section_wanted="$section_wanted" -v key="$key" '
function is_section(line) {
  return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*($|#)/
}
function section_name(line, s) {
  s = line
  sub(/^[[:space:]]*\[/, "", s)
  sub(/\][[:space:]]*($|#.*$)/, "", s)
  return s
}
function emit_if_match(line, trimmed, rest) {
  trimmed = line
  sub(/^[[:space:]]*/, "", trimmed)
  if (index(trimmed, key) != 1) {
    return
  }
  rest = substr(trimmed, length(key) + 1)
  if (rest !~ /^[[:space:]]*=/) {
    return
  }
  sub(/^[^=]*=[[:space:]]*/, "", trimmed)
  if (trimmed ~ /^"/) {
    sub(/^"/, "", trimmed)
    sub(/".*$/, "", trimmed)
    print trimmed
    exit
  }
  if (trimmed ~ /^\047/) {
    sub(/^\047/, "", trimmed)
    sub(/\047.*$/, "", trimmed)
    print trimmed
    exit
  }
}
is_section($0) {
  section = section_name($0)
  in_section = (section == section_wanted)
  next
}
in_section { emit_if_match($0) }
' "$cfg" 2>/dev/null | sed -n '1p'
}

codex_config_current_provider() {
  cfg="${1:-$(codex_config_file)}"
  codex_config_root_string_value model_provider "$cfg"
}

codex_config_third_party_provider_name_needs_normalize() {
  codex_provider_cfg="${1:-$(codex_config_file)}"
  [ -s "$codex_provider_cfg" ] || return 1
  codex_provider_id="${CODEX_ZH_PROVIDER_ID:-custom}"
  [ "$(codex_config_current_provider "$codex_provider_cfg")" = "$codex_provider_id" ] || return 1
  codex_provider_base="$(codex_config_section_string_value "$codex_provider_cfg" "model_providers.$codex_provider_id" base_url)"
  [ -n "$codex_provider_base" ] || return 1
  codex_provider_current_name="$(codex_config_section_string_value "$codex_provider_cfg" "model_providers.$codex_provider_id" name)"
  [ -z "$codex_provider_current_name" ] || [ "$codex_provider_current_name" = "$codex_provider_id" ]
}

codex_config_normalize_third_party_provider_name() {
  codex_provider_cfg="${1:-$(codex_config_file)}"
  codex_config_third_party_provider_name_needs_normalize "$codex_provider_cfg" || return 0
  codex_provider_id="${CODEX_ZH_PROVIDER_ID:-custom}"
  codex_provider_display_name="${CODEX_ZH_PROVIDER_NAME:-OpenAI}"
  codex_provider_display_name_esc="$(codex_toml_escape "$codex_provider_display_name")"
  codex_provider_cfg_tmp="$(codex_config_tmp_path "$codex_provider_cfg")"
  awk \
    -v provider="$codex_provider_id" \
    -v provider_name="$codex_provider_display_name_esc" '
function section_name(line, s) {
  s = line
  sub(/^[[:space:]]*\[/, "", s)
  sub(/\][[:space:]]*($|#.*$)/, "", s)
  return s
}
function is_section(line) {
  return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*($|#)/
}
function emit_missing_name() {
  if (in_provider && !provider_name_seen) {
    print "name = \"" provider_name "\""
    provider_name_seen = 1
  }
}
{
  if (is_section($0)) {
    emit_missing_name()
    section = section_name($0)
    in_provider = (section == "model_providers." provider)
    provider_name_seen = 0
    print
    next
  }
  if (in_provider && $0 ~ /^[[:space:]]*name[[:space:]]*=/) {
    print "name = \"" provider_name "\""
    provider_name_seen = 1
    next
  }
  print
}
END {
  emit_missing_name()
}
' "$codex_provider_cfg" > "$codex_provider_cfg_tmp"
  codex_config_atomic_install_file "$codex_provider_cfg_tmp" "$codex_provider_cfg" 600 ||
    codex_die "无法修复第三方 provider 名称：$codex_provider_cfg"
}

codex_config_is_full_permission() {
  cfg="${1:-$(codex_config_file)}"
  [ "$(codex_config_root_string_value approval_policy "$cfg")" = "never" ] || return 1
  [ "$(codex_config_root_string_value sandbox_mode "$cfg")" = "danger-full-access" ] || return 1
}

codex_config_apply_full_permission() {
  cfg="${1:-$(codex_config_file)}"
  [ -s "$cfg" ] || codex_die "缺少 $cfg，无法修复授权"
  codex_config_normalize_third_party_provider_name "$cfg"
  cfg_tmp="$(codex_config_tmp_path "$cfg")"
  awk '
function is_section(line) {
  return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*($|#)/
}
function emit_full_permission() {
  if (permission_done) {
    return
  }
  print "approval_policy = \"never\""
  print "sandbox_mode = \"danger-full-access\""
  permission_done = 1
}
{
  if (is_section($0)) {
    if (section == "") {
      emit_full_permission()
    }
    section = "section"
    print
    next
  }
  if (section == "" && $0 ~ /^[[:space:]]*approval_policy[[:space:]]*=/) {
    next
  }
  if (section == "" && $0 ~ /^[[:space:]]*sandbox_mode[[:space:]]*=/) {
    next
  }
  print
}
END {
  if (section == "") {
    emit_full_permission()
  }
}
' "$cfg" > "$cfg_tmp"
  codex_config_atomic_install_file "$cfg_tmp" "$cfg" 600 ||
    codex_die "无法写入授权配置：$cfg"
}

codex_config_strip_managed_block() {
  codex_strip_begin="$1"
  codex_strip_end="$2"
  codex_strip_input="$3"
  codex_strip_output="$4"
  awk -v begin="$codex_strip_begin" -v end="$codex_strip_end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$codex_strip_input" > "$codex_strip_output"
}

codex_config_set_hooks_feature() {
  codex_hooks_cfg="${1:-$(codex_config_file)}"
  codex_hooks_desired="${2:-true}"
  codex_hooks_home="$(codex_home)"
  mkdir -p "$codex_hooks_home"
  mkdir -p "$(dirname "$codex_hooks_cfg")" || codex_die "无法创建 hooks 配置目录：$(dirname "$codex_hooks_cfg")"
  codex_hooks_input="$codex_hooks_cfg"
  [ -f "$codex_hooks_input" ] || codex_hooks_input="/dev/null"
  codex_hooks_tmp="$(codex_config_tmp_path "$codex_hooks_cfg")"
  awk -v desired="$codex_hooks_desired" '
function is_section(line) {
  return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*($|#)/
}
function section_name(line, s) {
  s = line
  sub(/^[[:space:]]*\[/, "", s)
  sub(/\][[:space:]]*($|#.*$)/, "", s)
  return s
}
function flush_features() {
  if (section == "features" && !hooks_seen) {
    print "hooks = " desired
    hooks_seen = 1
  }
}
{
  if (is_section($0)) {
    flush_features()
    section = section_name($0)
    if (section == "features") {
      features_seen = 1
      hooks_seen = 0
    }
    print
    next
  }
  if (section == "features" && $0 ~ /^[[:space:]]*hooks[[:space:]]*=/) {
    print "hooks = " desired
    hooks_seen = 1
    next
  }
  print
}
END {
  flush_features()
  if (!features_seen) {
    print ""
    print "[features]"
    print "hooks = " desired
  }
}
' "$codex_hooks_input" > "$codex_hooks_tmp"
  codex_config_atomic_install_file "$codex_hooks_tmp" "$codex_hooks_cfg" 600 ||
    codex_die "无法写入 hooks 配置：$codex_hooks_cfg"
}

codex_config_append_default_hook_blocks() {
  codex_hooks_cfg="$1"
  mkdir -p "$(dirname "$codex_hooks_cfg")" || codex_die "无法创建 hooks 配置目录：$(dirname "$codex_hooks_cfg")"
  codex_hooks_strip_rtk="$codex_hooks_cfg.strip-rtk.$$"
  codex_hooks_strip_context="$codex_hooks_cfg.strip-context.$$"
  codex_hooks_strip_defaults="$codex_hooks_cfg.strip-session-defaults.$$"
  codex_hooks_out="$(codex_config_tmp_path "$codex_hooks_cfg")"
  codex_config_strip_managed_block \
    "# codex-for-tui-rtk-hook begin" \
    "# codex-for-tui-rtk-hook end" \
    "$codex_hooks_cfg" "$codex_hooks_strip_rtk"
  codex_config_strip_managed_block \
    "# codex-for-tui-context-hook begin" \
    "# codex-for-tui-context-hook end" \
    "$codex_hooks_strip_rtk" "$codex_hooks_strip_context"
  codex_config_strip_managed_block \
    "# codex-for-tui-session-defaults-hook begin" \
    "# codex-for-tui-session-defaults-hook end" \
    "$codex_hooks_strip_context" "$codex_hooks_strip_defaults"
  {
    cat "$codex_hooks_strip_defaults"
    if command -v codex-rtk >/dev/null 2>&1 && codex-rtk status >/dev/null 2>&1; then
      printf '\n# codex-for-tui-rtk-hook begin\n'
      printf '[[hooks.PreToolUse]]\n'
      printf 'matcher = "^Bash$"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-rtk hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "RTK compacting shell command"\n'
      printf '# codex-for-tui-rtk-hook end\n'
    fi
    if command -v codex-context >/dev/null 2>&1 && codex-context status >/dev/null 2>&1; then
      printf '\n# codex-for-tui-context-hook begin\n'
      printf '[[hooks.PreCompact]]\n'
      printf 'matcher = "manual|auto"\n\n'
      printf '[[hooks.PreCompact.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-context hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Recording context compact start"\n\n'
      printf '[[hooks.PostCompact]]\n'
      printf 'matcher = "manual|auto"\n\n'
      printf '[[hooks.PostCompact.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-context hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Recording context compact finish"\n\n'
      printf '[[hooks.SessionStart]]\n'
      printf 'matcher = "startup|resume|compact"\n\n'
      printf '[[hooks.SessionStart.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-context hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Recording Codex session start"\n'
      printf '# codex-for-tui-context-hook end\n'
    fi
    if command -v codex-session-defaults >/dev/null 2>&1 &&
      codex-session-defaults status >/dev/null 2>&1
    then
      printf '\n# codex-for-tui-session-defaults-hook begin\n'
      printf '[[hooks.UserPromptSubmit]]\n\n'
      printf '[[hooks.UserPromptSubmit.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-session-defaults hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Saving Codex session defaults"\n\n'
      printf '[[hooks.Stop]]\n\n'
      printf '[[hooks.Stop.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-session-defaults hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Saving Codex session defaults"\n'
      printf '# codex-for-tui-session-defaults-hook end\n'
    fi
  } > "$codex_hooks_out"
  rm -f "$codex_hooks_strip_rtk" "$codex_hooks_strip_context" "$codex_hooks_strip_defaults"
  codex_config_atomic_install_file "$codex_hooks_out" "$codex_hooks_cfg" 600 ||
    codex_die "无法写入默认 hooks 配置：$codex_hooks_cfg"
}

codex_config_strip_default_hook_blocks() {
  codex_hooks_cfg="$1"
  [ -f "$codex_hooks_cfg" ] || return 0
  codex_hooks_strip_rtk="$codex_hooks_cfg.strip-rtk.$$"
  codex_hooks_strip_context="$codex_hooks_cfg.strip-context.$$"
  codex_hooks_strip_defaults="$codex_hooks_cfg.strip-session-defaults.$$"
  codex_config_strip_managed_block \
    "# codex-for-tui-rtk-hook begin" \
    "# codex-for-tui-rtk-hook end" \
    "$codex_hooks_cfg" "$codex_hooks_strip_rtk"
  codex_config_strip_managed_block \
    "# codex-for-tui-context-hook begin" \
    "# codex-for-tui-context-hook end" \
    "$codex_hooks_strip_rtk" "$codex_hooks_strip_context"
  codex_config_strip_managed_block \
    "# codex-for-tui-session-defaults-hook begin" \
    "# codex-for-tui-session-defaults-hook end" \
    "$codex_hooks_strip_context" "$codex_hooks_strip_defaults"
  codex_config_atomic_install_file "$codex_hooks_strip_defaults" "$codex_hooks_cfg" 600 ||
    codex_die "无法清理默认 hooks 配置：$codex_hooks_cfg"
  rm -f "$codex_hooks_strip_rtk" "$codex_hooks_strip_context" "$codex_hooks_strip_defaults"
}

codex_config_append_managed_hook_blocks() {
  codex_hooks_req="$1"
  mkdir -p "$(dirname "$codex_hooks_req")" || return 1
  codex_hooks_strip="$codex_hooks_req.strip-managed.$$"
  codex_hooks_out="$(codex_config_tmp_path "$codex_hooks_req")"
  codex_config_strip_managed_block \
    "# codex-for-tui-managed-hooks begin" \
    "# codex-for-tui-managed-hooks end" \
    "$codex_hooks_req" "$codex_hooks_strip"
  {
    cat "$codex_hooks_strip"
    printf '\n# codex-for-tui-managed-hooks begin\n'
    if command -v codex-rtk >/dev/null 2>&1 && codex-rtk status >/dev/null 2>&1; then
      printf '[[hooks.PreToolUse]]\n'
      printf 'matcher = "^Bash$"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-rtk hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "RTK compacting shell command"\n\n'
    fi
    if command -v codex-context >/dev/null 2>&1 && codex-context status >/dev/null 2>&1; then
      printf '[[hooks.PreCompact]]\n'
      printf 'matcher = "manual|auto"\n\n'
      printf '[[hooks.PreCompact.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-context hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Recording context compact start"\n\n'
      printf '[[hooks.PostCompact]]\n'
      printf 'matcher = "manual|auto"\n\n'
      printf '[[hooks.PostCompact.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-context hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Recording context compact finish"\n\n'
      printf '[[hooks.SessionStart]]\n'
      printf 'matcher = "startup|resume|compact"\n\n'
      printf '[[hooks.SessionStart.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-context hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Recording Codex session start"\n'
    fi
    if command -v codex-session-defaults >/dev/null 2>&1 &&
      codex-session-defaults status >/dev/null 2>&1
    then
      printf '[[hooks.UserPromptSubmit]]\n\n'
      printf '[[hooks.UserPromptSubmit.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-session-defaults hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Saving Codex session defaults"\n\n'
      printf '[[hooks.Stop]]\n\n'
      printf '[[hooks.Stop.hooks]]\n'
      printf 'type = "command"\n'
      printf 'command = "codex-session-defaults hook"\n'
      printf 'timeout = 5\n'
      printf 'statusMessage = "Saving Codex session defaults"\n'
    fi
    printf '# codex-for-tui-managed-hooks end\n'
  } > "$codex_hooks_out"
  rm -f "$codex_hooks_strip"
  codex_config_atomic_install_file "$codex_hooks_out" "$codex_hooks_req" 644 ||
    return 1
}

codex_config_managed_hooks_available() {
  command -v codex-session-defaults >/dev/null 2>&1 &&
    codex-session-defaults status >/dev/null 2>&1 && return 0
  command -v codex-rtk >/dev/null 2>&1 && codex-rtk status >/dev/null 2>&1 && return 0
  command -v codex-context >/dev/null 2>&1 && codex-context status >/dev/null 2>&1 && return 0
  return 1
}

codex_config_managed_hooks_enabled() {
  codex_hooks_req="$(codex_config_requirements_file)"
  [ -s "$codex_hooks_req" ] || return 1
  grep -F '# codex-for-tui-managed-hooks begin' "$codex_hooks_req" >/dev/null 2>&1
}

codex_config_ensure_managed_hooks() {
  codex_hooks_req="$(codex_config_requirements_file)"
  codex_hooks_dir="$(dirname "$codex_hooks_req")"
  mkdir -p "$codex_hooks_dir" || return 1
  codex_config_set_hooks_feature "$codex_hooks_req" true
  codex_config_append_managed_hook_blocks "$codex_hooks_req"
  codex_config_strip_default_hook_blocks "$(codex_config_file)"
}

codex_config_ensure_default_hooks() {
  codex_hooks_cfg="$(codex_config_file)"
  codex_hooks_home="$(codex_home)"
  mkdir -p "$codex_hooks_home"
  codex_config_set_hooks_feature "$codex_hooks_cfg" true
  if codex_config_managed_hooks_enabled; then
    codex_config_strip_default_hook_blocks "$codex_hooks_cfg"
  else
    codex_config_append_default_hook_blocks "$codex_hooks_cfg"
  fi
}

codex_config_backup_current() {
  home_dir="$(codex_home)"
  state_root="$(codex_state_root)"
  stamp="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf '%s' "$$")"
  backup_dir="$state_root/backups/$stamp"
  made=0
  for file in config.toml auth.json model_catalog.json; do
    if [ -e "$home_dir/$file" ]; then
      mkdir -p "$backup_dir"
      cp "$home_dir/$file" "$backup_dir/$file"
      made=1
    fi
  done
  if [ -s "$(codex_config_official_marker_file)" ]; then
    mkdir -p "$backup_dir/install-state"
    cp "$(codex_config_official_marker_file)" "$backup_dir/install-state/official-login-mode"
    made=1
  fi
  [ "$made" -eq 0 ] || codex_info "已备份当前配置。"
}

codex_config_tty_read() {
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

codex_config_tty_confirm() {
  prompt="$1"
  default="${2:-n}"
  ans="$(codex_config_tty_read "$prompt" "$default")"
  case "$ans" in
    y|Y|yes|YES|Yes|是) return 0 ;;
    *) return 1 ;;
  esac
}

codex_config_is_back_choice() {
  case "$1" in
    b|B|back|BACK|Back|返回) return 0 ;;
    *) return 1 ;;
  esac
}

codex_config_is_exit_choice() {
  case "$1" in
    0|q|Q|quit|QUIT|Quit|exit|EXIT|Exit|退出) return 0 ;;
    *) return 1 ;;
  esac
}

codex_config_exit_config_mode() {
  codex_info "已退出配置模式。"
  exit 0
}

codex_config_profiles_root() {
  printf '%s/config-profiles\n' "$(codex_home)"
}

codex_config_v2_profiles_root() {
  printf '%s/config-profiles-v2\n' "$(codex_home)"
}

codex_config_profile_valid_name() {
  name="$1"
  [ -n "$name" ] || return 1
  case "$name" in
    "."|".."|*/*|*\\*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

codex_config_menu_repair_full_permission() {
  if ! codex_config_repair_full_permission; then
    codex_warn "全权限授权修复失败，已返回配置模式。"
    return 1
  fi
}

codex_config_repair_full_permission() {
  cfg="$(codex_config_file)"
  [ -s "$cfg" ] || codex_die "缺少 $cfg，无法修复授权"
  need_provider_name=0
  codex_config_third_party_provider_name_needs_normalize "$cfg" && need_provider_name=1
  if codex_config_is_full_permission "$cfg" && [ "$need_provider_name" -eq 0 ]; then
    codex_info "当前已是全权限模式：approval_policy=never，sandbox_mode=danger-full-access"
    return 0
  fi
  codex_config_backup_current
  codex_config_apply_full_permission "$cfg"
  if [ "$need_provider_name" -eq 1 ]; then
    codex_info "已修复第三方 provider 名称：name=${CODEX_ZH_PROVIDER_NAME:-OpenAI}"
  fi
  codex_info "已修复授权：approval_policy=never，sandbox_mode=danger-full-access"
}

# Configuration UI V2. V1 storage migration is implemented by the
# transactional Python engine; all public profile and menu entry points below
# use the V2 schema.

codex_config_v2_work_root() {
  printf '%s/config-v2-ui\n' "$(codex_state_root)"
}

codex_config_v2_json_value() {
  v2_json_file="$1"
  v2_json_path="$2"
  python3 - "$v2_json_file" "$v2_json_path" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        value = json.load(handle)
    for key in sys.argv[2].split("."):
        if not key:
            continue
        value = value[key]
except (OSError, KeyError, TypeError, ValueError):
    raise SystemExit(1)

if value is None:
    pass
elif value is True:
    print("true")
elif value is False:
    print("false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
else:
    print(value)
PY
}

codex_config_v2_run() {
  v2_run_output="$1"
  shift
  mkdir -p "$(dirname "$v2_run_output")"
  codex_config_engine_ensure
  if PYTHONNOUSERSITE=1 python3 \
    "$CODEX_CONFIG_ENGINE_RESOLVED_ROOT/libexec/codex-config-engine.py" \
    --codex-home "$(codex_home)" "$@" > "$v2_run_output"
  then
    return 0
  else
    v2_run_rc=$?
  fi
  v2_run_error="$(codex_config_v2_json_value "$v2_run_output" error 2>/dev/null || true)"
  [ -n "$v2_run_error" ] || v2_run_error="配置引擎操作失败"
  codex_warn "$v2_run_error"
  return "$v2_run_rc"
}

codex_config_v2_prompt_name() {
  v2_name_prompt="$1"
  v2_name_default="${2:-}"
  CODEX_CONFIG_V2_NAME=""
  while :; do
    v2_name_value="$(codex_config_tty_read "$v2_name_prompt（b 返回，0 退出）" "$v2_name_default")"
    codex_config_is_back_choice "$v2_name_value" && return 1
    codex_config_is_exit_choice "$v2_name_value" && codex_config_exit_config_mode
    if codex_config_profile_valid_name "$v2_name_value"; then
      CODEX_CONFIG_V2_NAME="$v2_name_value"
      return 0
    fi
    codex_warn "名称只能使用字母、数字、点、下划线和短横线。"
  done
}

codex_config_v2_read_secret() {
  v2_secret_prompt="$1"
  v2_secret_value=""
  if [ "${CODEX_ZH_FORCE_STDIN:-0}" != "1" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf '%s: ' "$v2_secret_prompt" > /dev/tty
    v2_stty_state="$(stty -g < /dev/tty 2>/dev/null || true)"
    [ -z "$v2_stty_state" ] || stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r v2_secret_value < /dev/tty || v2_secret_value=""
    [ -z "$v2_stty_state" ] || stty "$v2_stty_state" < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
  else
    printf '%s: ' "$v2_secret_prompt" >&2
    IFS= read -r v2_secret_value || v2_secret_value=""
  fi
  printf '%s' "$v2_secret_value"
}

codex_config_v2_write_auth_input() {
  v2_auth_path="$1"
  v2_auth_key="$2"
  mkdir -p "$(dirname "$v2_auth_path")"
  v2_auth_tmp="$(codex_config_tmp_path "$v2_auth_path")"
  {
    printf '{\n'
    printf '  "OPENAI_API_KEY": "%s"\n' "$(codex_json_escape "$v2_auth_key")"
    printf '}\n'
  } > "$v2_auth_tmp"
  mv "$v2_auth_tmp" "$v2_auth_path"
  chmod 600 "$v2_auth_path" 2>/dev/null || true
}

codex_config_v2_profile_lines() {
  v2_profiles_json="$1"
  python3 - "$v2_profiles_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
active = value.get("active_profile_id")
for item in value.get("profiles", []):
    name = str(item.get("name", "") or "")
    # Hide upgrade-spawned duplicates from the picker; they confuse the menu.
    if "-legacy" in name:
        continue
    fields = [
        item.get("id", ""),
        name,
        item.get("mode", ""),
        item.get("model", ""),
        item.get("reasoning_effort") or "",
        "1" if item.get("id") == active else "0",
        item.get("base_url") or "",
    ]
    print("|".join(str(field).replace("|", "/").replace("\n", " ") for field in fields))
PY
}

codex_config_v2_choose_profile() {
  v2_choose_prompt="${1:-请选择配置编号}"
  v2_choose_work="$(codex_config_v2_work_root)"
  v2_choose_json="$v2_choose_work/profiles.json"
  v2_choose_lines="$v2_choose_work/profiles.lines"
  CODEX_CONFIG_V2_PROFILE_ID=""
  CODEX_CONFIG_V2_PROFILE_NAME=""
  codex_config_v2_run "$v2_choose_json" profile list || return 1
  codex_config_v2_profile_lines "$v2_choose_json" > "$v2_choose_lines"
  [ -s "$v2_choose_lines" ] || {
    codex_warn "还没有配置档，请先新建配置。"
    return 1
  }
  while :; do
    printf '%s\n' "中转站列表（站级=名称/模型策略/API/Key；压缩与权限见通用项）：" >&2
    awk -F '|' '{
      active = ($6 == "1" ? " *当前" : "")
      effort = ($5 != "" ? "/" $5 : "")
      model = ($4 != "" ? $4 effort : "默认模型")
      url = ($7 != "" ? $7 : "")
      if (url != "") {
        printf "%2d. %s%s  模型策略=%s  API=%s\n", NR, $2, active, model, url
      } else {
        printf "%2d. %s%s  [%s]  模型策略=%s\n", NR, $2, active, $3, model
      }
    }' "$v2_choose_lines" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_choose_count="$(wc -l < "$v2_choose_lines" | tr -d ' ')"
    v2_choose_value="$(codex_config_tty_read "$v2_choose_prompt" "b")"
    codex_config_is_back_choice "$v2_choose_value" && return 1
    codex_config_is_exit_choice "$v2_choose_value" && codex_config_exit_config_mode
    case "$v2_choose_value" in
      *[!0-9]*|"") codex_warn "请输入有效编号，或输入 b 返回。"; continue ;;
    esac
    if [ "$v2_choose_value" -ge 1 ] 2>/dev/null &&
      [ "$v2_choose_value" -le "$v2_choose_count" ] 2>/dev/null
    then
      v2_choose_line="$(sed -n "${v2_choose_value}p" "$v2_choose_lines")"
      CODEX_CONFIG_V2_PROFILE_ID="$(printf '%s\n' "$v2_choose_line" | cut -d '|' -f 1)"
      CODEX_CONFIG_V2_PROFILE_NAME="$(printf '%s\n' "$v2_choose_line" | cut -d '|' -f 2)"
      return 0
    fi
    codex_warn "中转站编号超出范围。"
  done
}

codex_config_v2_catalog_lines() {
  v2_catalog_json="$1"
  python3 - "$v2_catalog_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for item in value.get("models", []):
    fields = [
        item.get("slug", ""),
        item.get("display_name", ""),
        ",".join(item.get("reasoning_levels") or []),
        item.get("default_reasoning_level") or "",
        item.get("resolved_context_window") or "",
        item.get("auto_compact_token_limit") or "",
        "1" if item.get("conservative_fallback") else "0",
    ]
    print("|".join(str(field).replace("|", "/").replace("\n", " ") for field in fields))
PY
}

codex_config_v2_choose_model() {
  v2_model_catalog="$1"
  v2_model_preferred="${2:-}"
  v2_model_allow_missing="${3:-0}"
  v2_model_work="$(codex_config_v2_work_root)"
  v2_model_json="$v2_model_work/catalog-inspect.json"
  v2_model_lines="$v2_model_work/catalog.lines"
  codex_config_v2_run "$v2_model_json" catalog inspect --catalog-file "$v2_model_catalog" || return 1
  codex_config_v2_catalog_lines "$v2_model_json" > "$v2_model_lines"
  if [ "$v2_model_allow_missing" = "1" ] && [ -n "$v2_model_preferred" ] &&
    ! awk -F '|' -v model="$v2_model_preferred" '$1 == model { found = 1 } END { exit !found }' "$v2_model_lines"
  then
    v2_model_extra="$v2_model_lines.extra"
    printf '%s|%s|||||1\n' "$v2_model_preferred" "$v2_model_preferred" > "$v2_model_extra"
    cat "$v2_model_lines" >> "$v2_model_extra"
    mv "$v2_model_extra" "$v2_model_lines"
  fi
  [ -s "$v2_model_lines" ] || {
    codex_warn "模型目录为空。"
    return 1
  }
  v2_model_default="1"
  if [ -n "$v2_model_preferred" ]; then
    v2_model_match="$(awk -F '|' -v model="$v2_model_preferred" '$1 == model { print NR; exit }' "$v2_model_lines")"
    [ -z "$v2_model_match" ] || v2_model_default="$v2_model_match"
  fi
  while :; do
    printf '%s\n' "可用模型：" >&2
    awk -F '|' '{
      context = ($5 != "" ? "  上下文 " $5 : "  能力未知")
      fallback = ($7 == "1" ? "  [保守模式]" : "")
      printf "%2d. %s%s%s\n", NR, $1, context, fallback
    }' "$v2_model_lines" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_model_count="$(wc -l < "$v2_model_lines" | tr -d ' ')"
    v2_model_choice="$(codex_config_tty_read "请选择模型编号" "$v2_model_default")"
    codex_config_is_back_choice "$v2_model_choice" && return 1
    codex_config_is_exit_choice "$v2_model_choice" && codex_config_exit_config_mode
    case "$v2_model_choice" in
      *[!0-9]*|"") codex_warn "请输入有效编号，或输入 b 返回。"; continue ;;
    esac
    if [ "$v2_model_choice" -ge 1 ] 2>/dev/null &&
      [ "$v2_model_choice" -le "$v2_model_count" ] 2>/dev/null
    then
      v2_model_line="$(sed -n "${v2_model_choice}p" "$v2_model_lines")"
      CODEX_CONFIG_V2_MODEL="$(printf '%s\n' "$v2_model_line" | cut -d '|' -f 1)"
      CODEX_CONFIG_V2_LEVELS="$(printf '%s\n' "$v2_model_line" | cut -d '|' -f 3)"
      CODEX_CONFIG_V2_DEFAULT_LEVEL="$(printf '%s\n' "$v2_model_line" | cut -d '|' -f 4)"
      return 0
    fi
    codex_warn "模型编号超出范围。"
  done
}

codex_config_v2_choose_reasoning() {
  v2_reasoning_levels="$1"
  v2_reasoning_preferred="${2:-}"
  v2_reasoning_work="$(codex_config_v2_work_root)"
  v2_reasoning_file="$v2_reasoning_work/reasoning-levels.txt"
  mkdir -p "$v2_reasoning_work"
  printf '%s\n' "$v2_reasoning_levels" | tr ',' '\n' | sed '/^$/d' > "$v2_reasoning_file"
  if [ ! -s "$v2_reasoning_file" ]; then
    CODEX_CONFIG_V2_REASONING=""
    codex_info "该模型未声明可用推理等级，将不写入 model_reasoning_effort。"
    return 0
  fi
  v2_reasoning_default="$v2_reasoning_preferred"
  if [ -z "$v2_reasoning_default" ] ||
    ! grep -F -x -- "$v2_reasoning_default" "$v2_reasoning_file" >/dev/null 2>&1
  then
    v2_reasoning_default="$CODEX_CONFIG_V2_DEFAULT_LEVEL"
  fi
  if [ -z "$v2_reasoning_default" ] ||
    ! grep -F -x -- "$v2_reasoning_default" "$v2_reasoning_file" >/dev/null 2>&1
  then
    if grep -F -x -- medium "$v2_reasoning_file" >/dev/null 2>&1; then
      v2_reasoning_default="medium"
    else
      v2_reasoning_default="$(sed -n '1p' "$v2_reasoning_file")"
    fi
  fi
  v2_reasoning_default_number="$(awk -v effort="$v2_reasoning_default" '$0 == effort { print NR; exit }' "$v2_reasoning_file")"
  while :; do
    printf '%s\n' "推理等级：" >&2
    awk '{ printf "%2d. %s\n", NR, $0 }' "$v2_reasoning_file" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_reasoning_count="$(wc -l < "$v2_reasoning_file" | tr -d ' ')"
    v2_reasoning_choice="$(codex_config_tty_read "请选择推理等级编号" "$v2_reasoning_default_number")"
    codex_config_is_back_choice "$v2_reasoning_choice" && return 1
    codex_config_is_exit_choice "$v2_reasoning_choice" && codex_config_exit_config_mode
    case "$v2_reasoning_choice" in
      *[!0-9]*|"") codex_warn "请输入有效编号，或输入 b 返回。"; continue ;;
    esac
    if [ "$v2_reasoning_choice" -ge 1 ] 2>/dev/null &&
      [ "$v2_reasoning_choice" -le "$v2_reasoning_count" ] 2>/dev/null
    then
      CODEX_CONFIG_V2_REASONING="$(sed -n "${v2_reasoning_choice}p" "$v2_reasoning_file")"
      return 0
    fi
    codex_warn "推理等级编号超出范围。"
  done
}

codex_config_v2_prepare() {
  v2_prepare_work="$(codex_config_v2_work_root)"
  v2_prepare_status="$v2_prepare_work/status.json"
  mkdir -p "$v2_prepare_work"
  codex_config_v2_run "$v2_prepare_status" status || return 1
  v2_prepare_schema="$(codex_config_v2_json_value "$v2_prepare_status" schema_version 2>/dev/null || printf '1')"
  v2_prepare_recovered="$(codex_config_v2_json_value "$v2_prepare_status" recovered_transaction 2>/dev/null || printf 'false')"
  [ "$v2_prepare_recovered" != "true" ] ||
    codex_warn "检测到上次未完成的配置事务，已自动恢复到操作前状态。"
  [ "$v2_prepare_schema" = "1" ] || return 0

  v2_prepare_policy="follow-model"
  if ! codex_config_has_runtime_config && [ "$(codex_config_v2_json_value "$v2_prepare_status" profile_count 2>/dev/null || printf '0')" = "0" ]; then
    codex_config_v2_run "$v2_prepare_work/migrate.json" migrate-v1 --compact-policy follow-model
    return $?
  fi

  printf '%s\n' "检测到旧版配置档。迁移会先创建完整 V1 备份，失败可自动恢复。" >&2
  if [ -s "$(codex_config_file)" ] &&
    grep -Eq '^[[:space:]]*model_auto_compact_token_limit[[:space:]]*=[[:space:]]*220000([[:space:]]|$)' "$(codex_config_file)"
  then
    printf '%s\n' "1. 跟随模型真实上下文与自动压缩阈值（推荐）" >&2
    printf '%s\n' "2. 保留固定 220000 压缩阈值" >&2
    printf '%s\n' "b. 返回，不迁移" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    while :; do
      v2_prepare_choice="$(codex_config_tty_read "请选择迁移策略" "1")"
      case "$v2_prepare_choice" in
        1|"") v2_prepare_policy="follow-model"; break ;;
        2) v2_prepare_policy="fixed"; break ;;
        b|B|back|BACK|返回) return 2 ;;
        0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
        *) codex_warn "请输入 1、2、b 或 0。" ;;
      esac
    done
  else
    codex_config_tty_confirm "迁移到事务型配置档结构？（可回滚）" "y" || return 2
  fi
  codex_config_v2_run "$v2_prepare_work/migrate.json" migrate-v1 --compact-policy "$v2_prepare_policy"
}

codex_config_v2_dirty_guard() {
  v2_dirty_reason="${1:-继续操作}"
  v2_dirty_work="$(codex_config_v2_work_root)"
  v2_dirty_status="$v2_dirty_work/dirty-status.json"
  codex_config_v2_run "$v2_dirty_status" status || return 1
  v2_dirty_value="$(codex_config_v2_json_value "$v2_dirty_status" runtime_dirty 2>/dev/null || printf 'false')"
  [ "$v2_dirty_value" = "true" ] || return 0
  v2_dirty_active="$(codex_config_v2_json_value "$v2_dirty_status" active_profile_id 2>/dev/null || true)"
  [ -n "$v2_dirty_active" ] || return 0
  v2_dirty_reasons="$(python3 - "$v2_dirty_status" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
print("、".join(value.get("runtime_dirty_reasons") or []))
PY
)"
  while :; do
    printf '%s\n' "检测到当前运行配置与配置档不同：$v2_dirty_reasons" >&2
    printf '%s\n' "$v2_dirty_reason 前请选择：" >&2
    printf '%s\n' "1. 同步到当前配置档（推荐）" >&2
    printf '%s\n' "2. 另存为新配置档" >&2
    printf '%s\n' "3. 暂不保存，继续" >&2
    printf '%s\n' "b. 取消并返回" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_dirty_choice="$(codex_config_tty_read "请输入选项编号" "1")"
    case "$v2_dirty_choice" in
      1|"")
        codex_config_v2_run "$v2_dirty_work/sync-current.json" profile sync-current "$v2_dirty_active"
        return $?
        ;;
      2)
        codex_config_v2_prompt_name "新配置名称" "profile-$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf '%s' "$$")" || return 1
        codex_config_v2_run "$v2_dirty_work/import-current.json" \
          profile import-current --name "$CODEX_CONFIG_V2_NAME" --activate
        return $?
        ;;
      3) return 0 ;;
      b|B|back|BACK|返回) return 1 ;;
      0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
      *) codex_warn "请输入 1、2、3、b 或 0。" ;;
    esac
  done
}

codex_config_v2_post_materialize() {
  codex_config_apply_full_permission "$(codex_config_file)"
  codex_config_ensure_default_hooks
}

codex_config_v2_build_catalog() {
  v2_build_base="$1"
  v2_build_key="$2"
  v2_build_work="$(codex_config_v2_work_root)/provider"
  mkdir -p "$v2_build_work"
  CODEX_CONFIG_V2_PROVIDER_JSON="$v2_build_work/models.json"
  CODEX_CONFIG_V2_PROVIDER_ERROR="$v2_build_work/models.err"
  CODEX_CONFIG_V2_CATALOG="$v2_build_work/model_catalog.json"
  codex_info "请求模型列表：$v2_build_base/models"
  if ! codex_config_fetch_models \
    "$v2_build_base" \
    "$v2_build_key" \
    "$CODEX_CONFIG_V2_PROVIDER_JSON" \
    "$CODEX_CONFIG_V2_PROVIDER_ERROR"
  then
    [ ! -s "$CODEX_CONFIG_V2_PROVIDER_ERROR" ] ||
      sed -n '1,12p' "$CODEX_CONFIG_V2_PROVIDER_ERROR" >&2 || true
    codex_warn "无法获取 Provider 模型列表；用户配置未修改。"
    return 1
  fi
  codex_config_v2_run "$v2_build_work/catalog-build.json" \
    catalog build \
    --provider-json "$CODEX_CONFIG_V2_PROVIDER_JSON" \
    --output "$CODEX_CONFIG_V2_CATALOG"
}

codex_config_v2_create_official() {
  codex_config_v2_dirty_guard "新建并切换配置" || return 1
  v2_official_default_name="${CODEX_CONFIG_REQUESTED_NAME:-default}"
  codex_config_v2_prompt_name "配置名称" "$v2_official_default_name" || return 1
  codex_config_engine_ensure
  v2_official_catalog="$CODEX_CONFIG_ENGINE_RESOLVED_ROOT/data/openai-models.json"
  codex_config_v2_choose_model "$v2_official_catalog" "${CODEX_ZH_DEFAULT_MODEL:-}" 0 || return 1
  codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "" || return 1
  v2_official_summary="$CODEX_CONFIG_V2_NAME / $CODEX_CONFIG_V2_MODEL"
  [ -z "$CODEX_CONFIG_V2_REASONING" ] ||
    v2_official_summary="$v2_official_summary / $CODEX_CONFIG_V2_REASONING"
  printf '%s\n' "将创建官方配置：$v2_official_summary" >&2
  codex_config_tty_confirm "确认创建并切换？" "y" || return 1
  v2_official_work="$(codex_config_v2_work_root)"
  codex_config_v2_run "$v2_official_work/create-official.json" \
    profile create \
    --name "$CODEX_CONFIG_V2_NAME" \
    --mode official \
    --model "$CODEX_CONFIG_V2_MODEL" \
    --reasoning-effort "$CODEX_CONFIG_V2_REASONING" \
    --activate || return 1
  codex_config_v2_post_materialize
  codex_info "已创建并切换配置：$CODEX_CONFIG_V2_NAME"
}

codex_config_v2_create_third_party() {
  codex_config_v2_dirty_guard "新建并切换配置" || return 1
  v2_create_default_name="${CODEX_CONFIG_REQUESTED_NAME:-default}"
  codex_config_v2_prompt_name "配置名称" "$v2_create_default_name" || return 1
  v2_create_default_base="${CODEX_ZH_API_BASE:-}"
  while :; do
    v2_create_raw_base="$(codex_config_tty_read "API Base URL（b 返回，0 退出）" "$v2_create_default_base")"
    codex_config_is_back_choice "$v2_create_raw_base" && return 1
    codex_config_is_exit_choice "$v2_create_raw_base" && codex_config_exit_config_mode
    codex_config_valid_api_base "$v2_create_raw_base" && break
    codex_warn "API Base URL 无效，必须是不含账号、查询参数或片段的 http(s) URL。"
  done
  v2_create_base="$(codex_config_normalize_api_base "$v2_create_raw_base")"
  v2_create_key="${CODEX_ZH_API_KEY:-}"
  while [ -z "$v2_create_key" ]; do
    v2_create_key="$(codex_config_v2_read_secret "API Key（输入 b 返回，0 退出）")"
    codex_config_is_back_choice "$v2_create_key" && return 1
    codex_config_is_exit_choice "$v2_create_key" && codex_config_exit_config_mode
    [ -n "$v2_create_key" ] || codex_warn "API Key 不能为空。"
  done
  codex_config_v2_build_catalog "$v2_create_base" "$v2_create_key" || return 1
  codex_config_v2_choose_model \
    "$CODEX_CONFIG_V2_CATALOG" \
    "${CODEX_ZH_DEFAULT_MODEL:-}" \
    0 || return 1
  codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "" || return 1
  printf '%s\n' "将创建第三方配置：$CODEX_CONFIG_V2_NAME" >&2
  printf '%s\n' "  Base URL: $v2_create_base" >&2
  v2_create_model_summary="$CODEX_CONFIG_V2_MODEL"
  [ -z "$CODEX_CONFIG_V2_REASONING" ] ||
    v2_create_model_summary="$v2_create_model_summary / $CODEX_CONFIG_V2_REASONING"
  printf '%s\n' "  模型: $v2_create_model_summary" >&2
  codex_config_tty_confirm "确认创建并切换？" "y" || return 1
  v2_create_work="$(codex_config_v2_work_root)"
  v2_create_auth="$v2_create_work/auth-input.json"
  codex_config_v2_write_auth_input "$v2_create_auth" "$v2_create_key"
  if codex_config_v2_run "$v2_create_work/create-third-party.json" \
    profile create \
    --name "$CODEX_CONFIG_V2_NAME" \
    --mode third_party \
    --provider-name "${CODEX_ZH_PROVIDER_NAME:-OpenAI}" \
    --base-url "$v2_create_base" \
    --model "$CODEX_CONFIG_V2_MODEL" \
    --reasoning-effort "$CODEX_CONFIG_V2_REASONING" \
    --auth-file "$v2_create_auth" \
    --catalog-file "$CODEX_CONFIG_V2_CATALOG" \
    --activate
  then
    rm -f "$v2_create_auth"
  else
    v2_create_rc=$?
    rm -f "$v2_create_auth"
    return "$v2_create_rc"
  fi
  codex_config_v2_post_materialize
  codex_info "已创建并切换配置：$CODEX_CONFIG_V2_NAME"
}

codex_config_v2_create_menu() {
  while :; do
    printf '%s\n' "新建配置：" >&2
    printf '%s\n' "1. 第三方 Responses API" >&2
    printf '%s\n' "2. OpenAI 官方登录" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_create_type="$(codex_config_tty_read "请选择配置类型" "1")"
    case "$v2_create_type" in
      1|"") codex_config_v2_create_third_party; return $? ;;
      2) codex_config_v2_create_official; return $? ;;
      b|B|back|BACK|返回) return 1 ;;
      0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
      *) codex_warn "请输入 1、2、b 或 0。" ;;
    esac
  done
}

codex_config_v2_format_compact_label() {
  v2_fmt_mode="${1:-follow-model}"
  v2_fmt_value="${2:-}"
  case "$v2_fmt_mode" in
    fixed)
      if [ -n "$v2_fmt_value" ]; then
        printf '固定 %s token' "$v2_fmt_value"
      else
        printf '固定阈值'
      fi
      ;;
    *)
      printf '跟随模型（全站共用）'
      ;;
  esac
}

codex_config_v2_show_profile() {
  v2_show_ref="$1"
  v2_show_work="$(codex_config_v2_work_root)"
  v2_show_json="$v2_show_work/profile-show.json"
  codex_config_v2_run "$v2_show_json" profile show "$v2_show_ref" || return 1
  python3 - "$v2_show_json" <<'PY' >&2
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
item = value["profile"]
mode = item.get("mode", "")
mode_label = "第三方" if mode == "third_party" else ("官方登录" if mode == "official" else mode)
print("—— 中转站（仅本站）——")
print(f"名称: {item.get('name', '')}")
print(f"ID: {item.get('id', '')}")
print(f"类型: {mode_label}")
print(f"模型策略: {item.get('model') or '默认'}" +
      (f" / {item.get('reasoning_effort')}" if item.get("reasoning_effort") else ""))
if mode == "third_party":
    print(f"API: {item.get('base_url') or '未设置'}")
    print(f"Provider: {item.get('provider_name') or 'custom'}")
print(f"Key: {'已保存' if item.get('has_auth') else '未保存'}（密钥不显示）")
print(f"模型目录: {'已保存' if item.get('has_catalog') else '未保存'}")
print(f"当前使用: {'是' if value.get('active') else '否'}")
policy = value.get("compact_policy") or {}
policy_mode = policy.get("mode") or "follow-model"
if policy_mode == "fixed" and policy.get("value"):
    compact_label = f"固定 {policy.get('value')} token"
else:
    compact_label = "跟随模型（全站共用）"
print("—— 通用项（全站共用，见主菜单第 7 项）——")
print(f"上下文/压缩: {compact_label}")
print("说明: 权限、TUI、features 等写在共用 config，不随站切换。")
PY
}

codex_config_v2_edit_official_field() {
  # field: name|model|all
  v2_edit_id="$1"
  v2_edit_json="$2"
  v2_edit_field="$3"
  v2_edit_name="$(codex_config_v2_json_value "$v2_edit_json" profile.name)"
  v2_edit_model="$(codex_config_v2_json_value "$v2_edit_json" profile.model 2>/dev/null || true)"
  v2_edit_effort="$(codex_config_v2_json_value "$v2_edit_json" profile.reasoning_effort 2>/dev/null || true)"
  CODEX_CONFIG_V2_NAME="$v2_edit_name"
  CODEX_CONFIG_V2_MODEL="$v2_edit_model"
  CODEX_CONFIG_V2_REASONING="$v2_edit_effort"
  case "$v2_edit_field" in
    name)
      codex_config_v2_prompt_name "配置名称" "$v2_edit_name" || return 1
      ;;
    model|all)
      if [ "$v2_edit_field" = "all" ]; then
        codex_config_v2_prompt_name "配置名称" "$v2_edit_name" || return 1
      fi
      codex_config_engine_ensure
      v2_edit_catalog="$CODEX_CONFIG_ENGINE_RESOLVED_ROOT/data/openai-models.json"
      codex_config_v2_choose_model "$v2_edit_catalog" "$v2_edit_model" 1 || return 1
      codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "$v2_edit_effort" || return 1
      ;;
    *)
      codex_warn "不支持的编辑项：$v2_edit_field"
      return 1
      ;;
  esac
  codex_config_tty_confirm "确认保存修改？" "y" || return 1
  v2_edit_work="$(codex_config_v2_work_root)"
  codex_config_v2_run "$v2_edit_work/edit-official.json" \
    profile update "$v2_edit_id" \
    --name "$CODEX_CONFIG_V2_NAME" \
    --model "$CODEX_CONFIG_V2_MODEL" \
    --reasoning-effort "$CODEX_CONFIG_V2_REASONING" || return 1
  codex_config_v2_post_materialize
  codex_info "已保存配置：$CODEX_CONFIG_V2_NAME"
}

codex_config_v2_edit_third_party_field() {
  # field: name|api|key|model|all
  v2_edit_id="$1"
  v2_edit_json="$2"
  v2_edit_field="$3"
  v2_edit_name="$(codex_config_v2_json_value "$v2_edit_json" profile.name)"
  v2_edit_base="$(codex_config_v2_json_value "$v2_edit_json" profile.base_url)"
  v2_edit_model="$(codex_config_v2_json_value "$v2_edit_json" profile.model)"
  v2_edit_effort="$(codex_config_v2_json_value "$v2_edit_json" profile.reasoning_effort 2>/dev/null || true)"
  v2_edit_provider="$(codex_config_v2_json_value "$v2_edit_json" profile.provider_name 2>/dev/null || true)"
  [ -n "$v2_edit_provider" ] || v2_edit_provider="${CODEX_ZH_PROVIDER_NAME:-OpenAI}"
  CODEX_CONFIG_V2_NAME="$v2_edit_name"
  v2_edit_new_base="$v2_edit_base"
  CODEX_CONFIG_V2_MODEL="$v2_edit_model"
  CODEX_CONFIG_V2_REASONING="$v2_edit_effort"
  v2_edit_auth_args=""
  v2_edit_catalog_args=""
  v2_edit_auth=""
  v2_edit_work="$(codex_config_v2_work_root)"
  v2_edit_existing_auth="$(codex_config_v2_profiles_root)/profiles/$v2_edit_id/auth.json"
  v2_edit_existing_key="$(codex_config_read_auth_key "$v2_edit_existing_auth" || true)"
  v2_edit_key=""

  case "$v2_edit_field" in
    name)
      codex_config_v2_prompt_name "配置名称" "$v2_edit_name" || return 1
      ;;
    api)
      while :; do
        v2_edit_raw_base="$(codex_config_tty_read "API Base URL（b 返回，0 退出）" "$v2_edit_base")"
        codex_config_is_back_choice "$v2_edit_raw_base" && return 1
        codex_config_is_exit_choice "$v2_edit_raw_base" && codex_config_exit_config_mode
        codex_config_valid_api_base "$v2_edit_raw_base" && break
        codex_warn "API Base URL 无效，必须是不含账号、查询参数或片段的 http(s) URL。"
      done
      v2_edit_new_base="$(codex_config_normalize_api_base "$v2_edit_raw_base")"
      # URL 变更后刷新目录，模型/推理尽量保留当前值。
      [ -n "$v2_edit_existing_key" ] || {
        codex_warn "该配置没有可保留的 API Key，请先改 Key。"
        return 1
      }
      codex_config_v2_build_catalog "$v2_edit_new_base" "$v2_edit_existing_key" || return 1
      if ! codex_config_v2_run "$v2_edit_work/edit-model-check.json" \
        catalog inspect \
        --catalog-file "$CODEX_CONFIG_V2_CATALOG" \
        --model "$v2_edit_model"
      then
        codex_warn "当前模型不在新 API 目录中，请重新选择模型。"
        codex_config_v2_choose_model "$CODEX_CONFIG_V2_CATALOG" "$v2_edit_model" 0 || return 1
        codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "$v2_edit_effort" || return 1
      else
        v2_edit_levels="$(codex_config_v2_json_value "$v2_edit_work/edit-model-check.json" model.reasoning_levels)"
        CODEX_CONFIG_V2_LEVELS="$v2_edit_levels"
        if [ -n "$v2_edit_effort" ] &&
          ! printf '%s\n' "$v2_edit_levels" | tr ',' '\n' | grep -F -x -- "$v2_edit_effort" >/dev/null 2>&1
        then
          codex_warn "当前推理等级不受新目录支持，请重新选择。"
          codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "" || return 1
        fi
      fi
      v2_edit_catalog_args=1
      ;;
    key)
      v2_edit_key="$(codex_config_v2_read_secret "API Key（输入新值；b 返回，0 退出）")"
      codex_config_is_back_choice "$v2_edit_key" && return 1
      codex_config_is_exit_choice "$v2_edit_key" && codex_config_exit_config_mode
      [ -n "$v2_edit_key" ] || {
        codex_warn "API Key 不能为空。"
        return 1
      }
      # 新 key 后刷新目录校验当前模型。
      codex_config_v2_build_catalog "$v2_edit_new_base" "$v2_edit_key" || return 1
      if ! codex_config_v2_run "$v2_edit_work/edit-key-model-check.json" \
        catalog inspect \
        --catalog-file "$CODEX_CONFIG_V2_CATALOG" \
        --model "$v2_edit_model"
      then
        codex_warn "当前模型不在该 Key 可见目录中，请重新选择模型。"
        codex_config_v2_choose_model "$CODEX_CONFIG_V2_CATALOG" "$v2_edit_model" 0 || return 1
        codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "$v2_edit_effort" || return 1
      fi
      v2_edit_auth="$v2_edit_work/auth-input.json"
      codex_config_v2_write_auth_input "$v2_edit_auth" "$v2_edit_key"
      v2_edit_auth_args=1
      v2_edit_catalog_args=1
      ;;
    model)
      [ -n "$v2_edit_existing_key" ] || {
        codex_warn "该配置没有 API Key，无法拉取模型目录。"
        return 1
      }
      codex_config_v2_build_catalog "$v2_edit_new_base" "$v2_edit_existing_key" || return 1
      codex_config_v2_choose_model "$CODEX_CONFIG_V2_CATALOG" "$v2_edit_model" 0 || return 1
      codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "$v2_edit_effort" || return 1
      v2_edit_catalog_args=1
      ;;
    all)
      codex_config_v2_prompt_name "配置名称" "$v2_edit_name" || return 1
      while :; do
        v2_edit_raw_base="$(codex_config_tty_read "API Base URL（b 返回，0 退出）" "$v2_edit_base")"
        codex_config_is_back_choice "$v2_edit_raw_base" && return 1
        codex_config_is_exit_choice "$v2_edit_raw_base" && codex_config_exit_config_mode
        codex_config_valid_api_base "$v2_edit_raw_base" && break
        codex_warn "API Base URL 无效，必须是不含账号、查询参数或片段的 http(s) URL。"
      done
      v2_edit_new_base="$(codex_config_normalize_api_base "$v2_edit_raw_base")"
      v2_edit_key="$(codex_config_v2_read_secret "API Key（留空保留当前，输入 b 返回，0 退出）")"
      codex_config_is_back_choice "$v2_edit_key" && return 1
      codex_config_is_exit_choice "$v2_edit_key" && codex_config_exit_config_mode
      [ -n "$v2_edit_key" ] || v2_edit_key="$v2_edit_existing_key"
      [ -n "$v2_edit_key" ] || {
        codex_warn "该配置没有可保留的 API Key。"
        return 1
      }
      codex_config_v2_build_catalog "$v2_edit_new_base" "$v2_edit_key" || return 1
      codex_config_v2_choose_model "$CODEX_CONFIG_V2_CATALOG" "$v2_edit_model" 0 || return 1
      codex_config_v2_choose_reasoning "$CODEX_CONFIG_V2_LEVELS" "$v2_edit_effort" || return 1
      v2_edit_auth="$v2_edit_work/auth-input.json"
      codex_config_v2_write_auth_input "$v2_edit_auth" "$v2_edit_key"
      v2_edit_auth_args=1
      v2_edit_catalog_args=1
      ;;
    *)
      codex_warn "不支持的编辑项：$v2_edit_field"
      return 1
      ;;
  esac

  codex_config_tty_confirm "确认保存修改？" "y" || {
    [ -z "$v2_edit_auth" ] || rm -f "$v2_edit_auth"
    return 1
  }

  set -- profile update "$v2_edit_id" \
    --name "$CODEX_CONFIG_V2_NAME" \
    --provider-name "$v2_edit_provider" \
    --base-url "$v2_edit_new_base" \
    --model "$CODEX_CONFIG_V2_MODEL" \
    --reasoning-effort "$CODEX_CONFIG_V2_REASONING"
  if [ -n "$v2_edit_auth_args" ] && [ -n "$v2_edit_auth" ]; then
    set -- "$@" --auth-file "$v2_edit_auth"
  fi
  if [ -n "$v2_edit_catalog_args" ] && [ -n "${CODEX_CONFIG_V2_CATALOG:-}" ]; then
    set -- "$@" --catalog-file "$CODEX_CONFIG_V2_CATALOG"
  fi
  if codex_config_v2_run "$v2_edit_work/edit-third-party.json" "$@"; then
    [ -z "$v2_edit_auth" ] || rm -f "$v2_edit_auth"
  else
    v2_edit_rc=$?
    [ -z "$v2_edit_auth" ] || rm -f "$v2_edit_auth"
    return "$v2_edit_rc"
  fi
  codex_config_v2_post_materialize
  codex_info "已保存配置：$CODEX_CONFIG_V2_NAME"
}

codex_config_v2_edit_menu() {
  codex_config_v2_dirty_guard "编辑配置" || return 1
  codex_config_v2_choose_profile "请选择要编辑的中转站编号" || return 1
  v2_edit_work="$(codex_config_v2_work_root)"
  v2_edit_json="$v2_edit_work/edit-profile.json"
  codex_config_v2_run "$v2_edit_json" profile show "$CODEX_CONFIG_V2_PROFILE_ID" || return 1
  v2_edit_mode="$(codex_config_v2_json_value "$v2_edit_json" profile.mode)"
  v2_edit_name="$(codex_config_v2_json_value "$v2_edit_json" profile.name)"
  v2_edit_model="$(codex_config_v2_json_value "$v2_edit_json" profile.model 2>/dev/null || true)"
  v2_edit_effort="$(codex_config_v2_json_value "$v2_edit_json" profile.reasoning_effort 2>/dev/null || true)"
  v2_edit_base="$(codex_config_v2_json_value "$v2_edit_json" profile.base_url 2>/dev/null || true)"
  while :; do
    printf '%s\n' "" >&2
    printf '%s\n' "编辑中转站：$v2_edit_name（只改本站字段；压缩/权限见主菜单通用项）" >&2
    case "$v2_edit_mode" in
      official)
        printf '%s\n' "当前模型策略：${v2_edit_model:-默认}${v2_edit_effort:+ / $v2_edit_effort}" >&2
        printf '%s\n' "1. 改名称" >&2
        printf '%s\n' "2. 改模型策略（模型 + 推理）" >&2
        printf '%s\n' "3. 全部重设（名称 + 模型策略）" >&2
        printf '%s\n' "b. 返回上一层" >&2
        printf '%s\n' "0. 退出，不启动 Codex" >&2
        v2_edit_choice="$(codex_config_tty_read "请选择要改的字段" "b")"
        case "$v2_edit_choice" in
          1) codex_config_v2_edit_official_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" name; return $? ;;
          2) codex_config_v2_edit_official_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" model; return $? ;;
          3) codex_config_v2_edit_official_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" all; return $? ;;
          b|B|back|BACK|返回) return 1 ;;
          0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
          *) codex_warn "请输入 1、2、3、b 或 0。" ;;
        esac
        ;;
      third_party)
        printf '%s\n' "当前 API：${v2_edit_base:-未设置}" >&2
        printf '%s\n' "当前模型策略：${v2_edit_model:-默认}${v2_edit_effort:+ / $v2_edit_effort}" >&2
        printf '%s\n' "1. 改名称" >&2
        printf '%s\n' "2. 改 API（Base URL，必要时重选模型）" >&2
        printf '%s\n' "3. 改 Key" >&2
        printf '%s\n' "4. 改模型策略（模型 + 推理）" >&2
        printf '%s\n' "5. 全部重设（名称/API/Key/模型）" >&2
        printf '%s\n' "b. 返回上一层" >&2
        printf '%s\n' "0. 退出，不启动 Codex" >&2
        v2_edit_choice="$(codex_config_tty_read "请选择要改的字段" "b")"
        case "$v2_edit_choice" in
          1) codex_config_v2_edit_third_party_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" name; return $? ;;
          2) codex_config_v2_edit_third_party_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" api; return $? ;;
          3) codex_config_v2_edit_third_party_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" key; return $? ;;
          4) codex_config_v2_edit_third_party_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" model; return $? ;;
          5) codex_config_v2_edit_third_party_field "$CODEX_CONFIG_V2_PROFILE_ID" "$v2_edit_json" all; return $? ;;
          b|B|back|BACK|返回) return 1 ;;
          0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
          *) codex_warn "请输入 1–5、b 或 0。" ;;
        esac
        ;;
      *)
        codex_warn "未知配置类型：$v2_edit_mode"
        return 1
        ;;
    esac
  done
}

codex_config_v2_use_menu() {
  codex_config_v2_choose_profile "请选择要切换的配置编号" || return 1
  v2_use_id="$CODEX_CONFIG_V2_PROFILE_ID"
  v2_use_name="$CODEX_CONFIG_V2_PROFILE_NAME"
  codex_config_v2_dirty_guard "切换配置" || return 1
  v2_use_work="$(codex_config_v2_work_root)"
  codex_config_v2_run "$v2_use_work/activate.json" profile activate "$v2_use_id" || return 1
  codex_config_v2_post_materialize
  codex_info "已切换配置：$v2_use_name"
}

codex_config_v2_delete_menu() {
  codex_config_v2_choose_profile "请选择要删除的配置编号" || return 1
  v2_delete_id="$CODEX_CONFIG_V2_PROFILE_ID"
  v2_delete_name="$CODEX_CONFIG_V2_PROFILE_NAME"
  codex_config_tty_confirm "确认删除配置 $v2_delete_name？当前配置不能直接删除" "n" || return 1
  v2_delete_work="$(codex_config_v2_work_root)"
  codex_config_v2_run "$v2_delete_work/delete.json" profile delete "$v2_delete_id" || return 1
  codex_info "已删除配置：$v2_delete_name"
}

codex_config_v2_view_menu() {
  codex_config_v2_choose_profile "请选择要查看的配置编号" || return 1
  codex_config_v2_show_profile "$CODEX_CONFIG_V2_PROFILE_ID"
}

codex_config_v2_compact_menu() {
  v2_compact_work="$(codex_config_v2_work_root)"
  v2_compact_show="$v2_compact_work/compact-show.json"
  codex_config_v2_run "$v2_compact_show" compact-policy show || return 1
  v2_compact_mode="$(codex_config_v2_json_value "$v2_compact_show" compact_policy.mode)"
  v2_compact_value="$(codex_config_v2_json_value "$v2_compact_show" compact_policy.value 2>/dev/null || true)"
  v2_compact_label="$(codex_config_v2_format_compact_label "$v2_compact_mode" "$v2_compact_value")"
  printf '%s\n' "" >&2
  printf '%s\n' "通用：上下文与压缩策略（全站共用，不随中转站切换）" >&2
  printf '%s\n' "当前：$v2_compact_label" >&2
  while :; do
    printf '%s\n' "1. 跟随模型目录，由 Codex 按真实窗口计算（推荐）" >&2
    printf '%s\n' "2. 使用固定 token 阈值" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_compact_choice="$(codex_config_tty_read "请选择压缩策略" "1")"
    case "$v2_compact_choice" in
      1|"")
        codex_config_v2_run "$v2_compact_work/compact-follow.json" compact-policy follow-model || return $?
        codex_info "已设为跟随模型（全站共用）。"
        return 0
        ;;
      2)
        while :; do
          v2_compact_fixed="$(codex_config_tty_read "固定 token 阈值（b 返回，0 退出）" "${v2_compact_value:-250000}")"
          codex_config_is_back_choice "$v2_compact_fixed" && return 1
          codex_config_is_exit_choice "$v2_compact_fixed" && codex_config_exit_config_mode
          case "$v2_compact_fixed" in
            *[!0-9]*|"") codex_warn "请输入正整数。"; continue ;;
          esac
          [ "$v2_compact_fixed" -gt 0 ] 2>/dev/null || { codex_warn "请输入正整数。"; continue; }
          codex_config_v2_run "$v2_compact_work/compact-fixed.json" compact-policy fixed "$v2_compact_fixed" || return $?
          codex_info "已设为固定 $v2_compact_fixed token（全站共用）。"
          return 0
        done
        ;;
      b|B|back|BACK|返回) return 1 ;;
      0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
      *) codex_warn "请输入 1、2、b 或 0。" ;;
    esac
  done
}

codex_config_refresh_models() {
  codex_config_v2_prepare || return 1
  v2_refresh_work="$(codex_config_v2_work_root)"
  v2_refresh_status="$v2_refresh_work/refresh-status.json"
  codex_config_v2_run "$v2_refresh_status" status || return 1
  v2_refresh_active="$(codex_config_v2_json_value "$v2_refresh_status" active_profile_id 2>/dev/null || true)"
  [ -n "$v2_refresh_active" ] || {
    codex_warn "当前没有已激活配置。"
    return 1
  }
  v2_refresh_profile="$v2_refresh_work/refresh-profile.json"
  codex_config_v2_run "$v2_refresh_profile" profile show "$v2_refresh_active" || return 1
  v2_refresh_mode="$(codex_config_v2_json_value "$v2_refresh_profile" profile.mode)"
  [ "$v2_refresh_mode" = "third_party" ] || {
    codex_warn "官方配置使用 Codex 官方模型目录，不需要请求第三方 /models。"
    return 1
  }
  v2_refresh_base="$(codex_config_v2_json_value "$v2_refresh_profile" profile.base_url)"
  v2_refresh_model="$(codex_config_v2_json_value "$v2_refresh_profile" profile.model)"
  v2_refresh_effort="$(codex_config_v2_json_value "$v2_refresh_profile" profile.reasoning_effort 2>/dev/null || true)"
  v2_refresh_auth="$(codex_config_v2_profiles_root)/profiles/$v2_refresh_active/auth.json"
  v2_refresh_key="$(codex_config_read_auth_key "$v2_refresh_auth" || true)"
  [ -n "$v2_refresh_key" ] || {
    codex_warn "当前配置没有 API Key。"
    return 1
  }
  codex_config_v2_build_catalog "$v2_refresh_base" "$v2_refresh_key" || return 1
  v2_refresh_model_json="$v2_refresh_work/refresh-model-check.json"
  if ! codex_config_v2_run "$v2_refresh_model_json" \
    catalog inspect \
    --catalog-file "$CODEX_CONFIG_V2_CATALOG" \
    --model "$v2_refresh_model"
  then
    codex_warn "当前模型已不在 Provider 模型列表中。请使用“编辑配置”选择新模型。"
    return 1
  fi
  v2_refresh_levels="$(codex_config_v2_json_value "$v2_refresh_model_json" model.reasoning_levels)"
  if [ -n "$v2_refresh_effort" ] &&
    ! python3 - "$v2_refresh_model_json" "$v2_refresh_effort" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
raise SystemExit(0 if sys.argv[2] in value["model"]["reasoning_levels"] else 1)
PY
  then
    codex_warn "当前推理等级已不受该模型支持。请使用“编辑配置”重新选择。"
    return 1
  fi
  codex_config_v2_run "$v2_refresh_work/refresh-update.json" \
    profile update "$v2_refresh_active" \
    --catalog-file "$CODEX_CONFIG_V2_CATALOG" || return 1
  codex_config_v2_post_materialize
  codex_info "模型目录已刷新；当前模型和推理等级保持不变。"
}

codex_config_v2_initialize_official() {
  codex_config_v2_prepare || return 1
  v2_init_name="${CODEX_CONFIG_REQUESTED_NAME:-default}"
  v2_init_work="$(codex_config_v2_work_root)"
  if codex_config_v2_run "$v2_init_work/init-show.json" profile show "$v2_init_name" 2>/dev/null; then
    codex_config_v2_run "$v2_init_work/init-activate.json" profile activate "$v2_init_name" || return 1
  else
    codex_config_v2_run "$v2_init_work/init-create.json" \
      profile create \
      --name "$v2_init_name" \
      --mode official \
      --activate || return 1
  fi
  codex_config_v2_post_materialize
  codex_info "已启用官方登录配置：$v2_init_name"
}

codex_config_prompt_official() {
  codex_config_v2_prepare || return 1
  codex_config_v2_create_official
}

codex_config_prompt_third_party() {
  v2_prompt_mode="${1:-new}"
  codex_config_v2_prepare || return 1
  if [ "$v2_prompt_mode" = "edit" ]; then
    codex_config_v2_edit_menu
  else
    codex_config_v2_create_third_party
  fi
}

codex_config_profile_list() {
  codex_config_engine_ensure
  v2_list_work="$(codex_config_v2_work_root)"
  v2_list_status="$v2_list_work/list-status.json"
  codex_config_v2_run "$v2_list_status" status || return 1
  if [ "$(codex_config_v2_json_value "$v2_list_status" schema_version)" = "1" ]; then
    v2_list_root="$(codex_config_profiles_root)"
    [ -d "$v2_list_root" ] || return 0
    find "$v2_list_root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
    return 0
  fi
  v2_list_json="$v2_list_work/list.json"
  codex_config_v2_run "$v2_list_json" profile list || return 1
  python3 - "$v2_list_json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for item in value.get("profiles", []):
    print(item.get("name", ""))
PY
}

codex_config_profile_use() {
  v2_profile_ref="$1"
  codex_config_v2_prepare || return 1
  codex_config_v2_dirty_guard "切换配置" || return 1
  v2_profile_work="$(codex_config_v2_work_root)"
  codex_config_v2_run "$v2_profile_work/profile-use.json" profile activate "$v2_profile_ref" || return 1
  codex_config_v2_post_materialize
}

codex_config_profile_save() {
  v2_profile_name="$1"
  codex_config_v2_prepare || return 1
  v2_profile_work="$(codex_config_v2_work_root)"
  if codex_config_v2_run "$v2_profile_work/profile-save-show.json" profile show "$v2_profile_name" 2>/dev/null; then
    v2_profile_id="$(codex_config_v2_json_value "$v2_profile_work/profile-save-show.json" profile.id)"
    v2_profile_active="$(codex_config_v2_json_value "$v2_profile_work/profile-save-show.json" active)"
    [ "$v2_profile_active" = "true" ] || {
      codex_warn "同名配置已存在且不是当前配置；未覆盖。"
      return 3
    }
    codex_config_v2_run "$v2_profile_work/profile-save-sync.json" profile sync-current "$v2_profile_id"
  else
    codex_config_v2_run "$v2_profile_work/profile-save-import.json" \
      profile import-current \
      --name "$v2_profile_name" \
      --activate
  fi
}

codex_config_profile_new() {
  CODEX_CONFIG_REQUESTED_NAME="$1"
  codex_config_prompt_third_party new
  unset CODEX_CONFIG_REQUESTED_NAME
}

codex_config_menu() {
  if [ "${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-0}" != "0" ] && [ "${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-0}" != "" ]; then
    # Depth>0 means a recursive call from inside an active menu tree.
    if [ "${CODEX_FOR_TUI_CONFIG_MENU_DEPTH}" -ge 1 ] 2>/dev/null; then
      codex_warn "配置模式已在运行，忽略连环嵌套进入。"
      return 1
    fi
  fi
  CODEX_FOR_TUI_CONFIG_MENU_DEPTH=$(( ${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-0} + 1 ))
  export CODEX_FOR_TUI_CONFIG_MENU_DEPTH
  if codex_config_v2_prepare; then
    :
  else
    v2_menu_prepare_rc=$?
    if [ "$v2_menu_prepare_rc" -eq 2 ]; then
      codex_info "已返回 shell，未迁移配置。"
      CODEX_FOR_TUI_CONFIG_MENU_DEPTH=$(( ${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-1} - 1 ))
      export CODEX_FOR_TUI_CONFIG_MENU_DEPTH
      return 0
    fi
    CODEX_FOR_TUI_CONFIG_MENU_DEPTH=$(( ${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-1} - 1 ))
    export CODEX_FOR_TUI_CONFIG_MENU_DEPTH
    return "$v2_menu_prepare_rc"
  fi
  while :; do
    v2_menu_work="$(codex_config_v2_work_root)"
    v2_menu_status="$v2_menu_work/menu-status.json"
    codex_config_v2_run "$v2_menu_status" status || return 1
    v2_menu_active="$(codex_config_v2_json_value "$v2_menu_status" active_profile_id 2>/dev/null || true)"
    v2_menu_label="无"
    v2_menu_station_detail=""
    if [ -n "$v2_menu_active" ]; then
      if codex_config_v2_run "$v2_menu_work/menu-active.json" profile show "$v2_menu_active"; then
        v2_menu_label="$(codex_config_v2_json_value "$v2_menu_work/menu-active.json" profile.name)"
        v2_menu_model="$(codex_config_v2_json_value "$v2_menu_work/menu-active.json" profile.model 2>/dev/null || true)"
        v2_menu_effort="$(codex_config_v2_json_value "$v2_menu_work/menu-active.json" profile.reasoning_effort 2>/dev/null || true)"
        v2_menu_base="$(codex_config_v2_json_value "$v2_menu_work/menu-active.json" profile.base_url 2>/dev/null || true)"
        v2_menu_station_detail="${v2_menu_model:-默认}${v2_menu_effort:+ / $v2_menu_effort}"
        [ -z "$v2_menu_base" ] || v2_menu_station_detail="$v2_menu_station_detail  $v2_menu_base"
        [ "$(codex_config_v2_json_value "$v2_menu_status" runtime_dirty)" != "true" ] ||
          v2_menu_label="$v2_menu_label（运行配置有未保存变化）"
      fi
    fi
    v2_menu_compact_mode="$(codex_config_v2_json_value "$v2_menu_status" compact_policy.mode 2>/dev/null || true)"
    v2_menu_compact_value="$(codex_config_v2_json_value "$v2_menu_status" compact_policy.value 2>/dev/null || true)"
    if [ -z "$v2_menu_compact_mode" ] && [ -n "$v2_menu_active" ] && [ -f "$v2_menu_work/menu-active.json" ]; then
      v2_menu_compact_mode="$(codex_config_v2_json_value "$v2_menu_work/menu-active.json" compact_policy.mode 2>/dev/null || true)"
      v2_menu_compact_value="$(codex_config_v2_json_value "$v2_menu_work/menu-active.json" compact_policy.value 2>/dev/null || true)"
    fi
    [ -n "$v2_menu_compact_mode" ] || v2_menu_compact_mode="follow-model"
    v2_menu_compact_label="$(codex_config_v2_format_compact_label "$v2_menu_compact_mode" "$v2_menu_compact_value")"
    printf '%s\n' "" >&2
    printf '%s\n' "Codex 配置模式" >&2
    printf '%s\n' "当前中转站：$v2_menu_label${v2_menu_station_detail:+  ($v2_menu_station_detail)}" >&2
    printf '%s\n' "通用策略：压缩=$v2_menu_compact_label；权限/TUI/features 全站共用" >&2
    printf '%s\n' "结构：站级=名称/模型策略/API/Key；通用=上下文·压缩·权限（第 7–8 项）" >&2
    printf '%s\n' "—— 中转站 ——" >&2
    printf '%s\n' "1. 新建中转站" >&2
    printf '%s\n' "2. 选择中转站" >&2
    printf '%s\n' "3. 编辑中转站字段（名称/API/Key/模型策略）" >&2
    printf '%s\n' "4. 查看中转站" >&2
    printf '%s\n' "5. 删除中转站" >&2
    printf '%s\n' "6. 刷新当前模型目录" >&2
    printf '%s\n' "—— 通用（全站共用）——" >&2
    printf '%s\n' "7. 通用：上下文与压缩策略" >&2
    printf '%s\n' "8. 通用：修复全权限授权" >&2
    printf '%s\n' "—— 退出 ——" >&2
    printf '%s\n' "9. 保存并退出配置模式" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    v2_menu_choice="$(codex_config_tty_read "请输入选项编号" "9")"
    case "$v2_menu_choice" in
      1) codex_config_v2_create_menu || true ;;
      2) codex_config_v2_use_menu || true ;;
      3) codex_config_v2_edit_menu || true ;;
      4) codex_config_v2_view_menu || true ;;
      5) codex_config_v2_delete_menu || true ;;
      6) codex_config_refresh_models || true ;;
      7) codex_config_v2_compact_menu || true ;;
      8) codex_config_menu_repair_full_permission || true ;;
      9|"")
        codex_config_v2_dirty_guard "退出配置模式" || continue
        codex_info "已退出配置模式。"
        CODEX_FOR_TUI_CONFIG_MENU_DEPTH=$(( ${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-1} - 1 ))
        export CODEX_FOR_TUI_CONFIG_MENU_DEPTH
        return 0
        ;;
      0|q|Q|quit|QUIT|退出)
        codex_config_v2_dirty_guard "退出配置模式" || continue
        CODEX_FOR_TUI_CONFIG_MENU_DEPTH=$(( ${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-1} - 1 ))
        export CODEX_FOR_TUI_CONFIG_MENU_DEPTH
        codex_config_exit_config_mode
        ;;
      b|B|back|BACK|返回)
        codex_config_v2_dirty_guard "退出配置模式" || continue
        codex_info "已退出配置模式。"
        CODEX_FOR_TUI_CONFIG_MENU_DEPTH=$(( ${CODEX_FOR_TUI_CONFIG_MENU_DEPTH:-1} - 1 ))
        export CODEX_FOR_TUI_CONFIG_MENU_DEPTH
        return 0
        ;;
      *) codex_warn "请输入 0 到 9，或输入 b 返回。" ;;
    esac
  done
}
