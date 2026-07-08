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

codex_config_mark_official_mode() {
  codex_config_backup_current
  marker="$(codex_config_official_marker_file)"
  marker_tmp="$(codex_config_tmp_path "$marker")"
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "official-login" > "$marker_tmp" || codex_die "无法写入官方登录标记临时文件"
  codex_config_atomic_install_file "$marker_tmp" "$marker" 600 ||
    codex_die "无法写入官方登录标记"
  codex_config_ensure_default_hooks
  codex_config_apply_full_permission "$(codex_config_file)"
}

codex_config_clear_official_mode() {
  codex_config_atomic_remove_file "$(codex_config_official_marker_file)" ||
    codex_die "无法清除官方登录标记"
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
  host_path="$(printf '%s' "$cleaned" | sed 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##')"
  host="$(printf '%s' "$host_path" | sed 's#[/?#].*##')"
  [ -n "$host" ]
}

codex_config_read_auth_key() {
  file="${1:-$(codex_config_auth_file)}"
  [ -s "$file" ] || return 1
  sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | sed -n '1p'
}

codex_config_write_auth_json() {
  api_key="$1"
  home_dir="$(codex_home)"
  codex_ensure_private_dir "$home_dir"
  auth_file="$home_dir/auth.json"
  auth_tmp="$(codex_config_tmp_path "$auth_file")"
  {
    printf '{\n'
    printf '  "OPENAI_API_KEY": "%s"\n' "$(codex_json_escape "$api_key")"
    printf '}\n'
  } > "$auth_tmp"
  codex_config_atomic_install_file "$auth_tmp" "$auth_file" 600 ||
    codex_die "无法写入 auth.json"
}

codex_config_write_auth_helper() {
  home_dir="$(codex_home)"
  helper_dir="$home_dir/bin"
  helper="$helper_dir/provider-api-key"
  codex_ensure_private_dir "$home_dir"
  mkdir -p "$helper_dir"
  helper_tmp="$(codex_config_tmp_path "$helper")"
  cat > "$helper_tmp" <<'EOF'
#!/usr/bin/env sh
auth_file="${CODEX_HOME:-$HOME/.codex}/auth.json"
sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$auth_file" | sed -n '1p'
EOF
  codex_config_atomic_install_file "$helper_tmp" "$helper" 700 ||
    codex_die "无法写入 API Key helper"
  printf '%s\n' "$helper"
}

codex_config_validate_default_model() {
  default_model="$1"
  models_file="$2"
  [ -n "$default_model" ] || codex_die "默认模型为空，未写入 config.toml"
  if [ "$(printf '%s' "$default_model" | wc -l | tr -d ' ')" != "0" ]; then
    codex_die "默认模型包含换行，未写入 config.toml"
  fi
  grep -F -x -- "$default_model" "$models_file" >/dev/null 2>&1 ||
    codex_die "默认模型不在模型列表中，未写入 config.toml：$default_model"
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

codex_config_parse_models() {
  json_file="$1"
  if codex_have jq; then
    jq -r '.data[]?.id // empty' "$json_file" 2>/dev/null | sed '/^$/d'
  else
    sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json_file" | sed '/^$/d'
  fi
}

codex_config_model_display_name() {
  printf '%s' "$1"
}

codex_config_write_model_catalog() {
  models_file="$1"
  default_model="${2:-}"
  out_json="$3"
  auto_limit="${CODEX_ZH_AUTO_COMPACT_TOKEN_LIMIT:-220000}"
  catalog_tmp="$(codex_config_tmp_path "$out_json")"
  catalog_dedup="$out_json.models.tmp.$$"
  mkdir -p "$(dirname "$out_json")"
  if [ -s "$models_file" ]; then
    awk 'NF && !seen[$0]++ { print }' "$models_file" > "$catalog_dedup"
  elif [ -n "$default_model" ]; then
    printf '%s\n' "$default_model" > "$catalog_dedup"
  else
    codex_die "没有可写入 model_catalog_json 的模型名"
  fi

  {
    printf '{\n'
    printf '  "models": [\n'
    count=0
    while IFS= read -r model; do
      [ -n "$model" ] || continue
      model_esc="$(codex_json_escape "$model")"
      name_esc="$(codex_json_escape "$(codex_config_model_display_name "$model")")"
      [ "$count" -eq 0 ] || printf ',\n'
      cat <<EOF
    {
      "prefer_websockets": true,
      "support_verbosity": true,
      "default_verbosity": "low",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text",
      "input_modalities": ["text", "image"],
      "supports_image_detail_original": true,
      "truncation_policy": {"mode": "tokens", "limit": 10000},
      "supports_parallel_tool_calls": true,
      "context_window": 272000,
      "max_context_window": 272000,
      "auto_compact_token_limit": $auto_limit,
      "reasoning_summary_format": "experimental",
      "default_reasoning_summary": "none",
      "additional_speed_tiers": ["fast"],
      "service_tiers": [
        {"id": "priority", "name": "Fast", "description": "Priority processing."}
      ],
      "default_service_tier": null,
      "slug": "$model_esc",
      "display_name": "$name_esc",
      "description": "$name_esc",
      "default_reasoning_level": "medium",
      "supported_reasoning_levels": [
        {"effort": "low", "description": "响应更快，推理较轻"},
        {"effort": "medium", "description": "在日常任务中平衡速度和推理深度"},
        {"effort": "high", "description": "为复杂问题提供更深推理"},
        {"effort": "xhigh", "description": "为复杂问题提供极高推理深度"}
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "minimal_client_version": "0.98.0",
      "supported_in_api": true,
      "availability_nux": null,
      "upgrade": null,
      "priority": 4,
      "base_instructions": "",
      "model_messages": null,
      "supports_reasoning_summaries": true,
      "effective_context_window_percent": 95,
      "experimental_supported_tools": [],
      "supports_search_tool": true,
      "use_responses_lite": false
    }
EOF
      count=$((count + 1))
    done < "$catalog_dedup"
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } > "$catalog_tmp"
  codex_config_atomic_install_file "$catalog_tmp" "$out_json" 600 ||
    codex_die "无法写入 model_catalog_json：$out_json"
  rm -f "$catalog_dedup"
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

codex_config_any_string_value() {
  key="$1"
  cfg="${2:-$(codex_config_file)}"
  [ -r "$cfg" ] || return 0
  awk -v key="$key" '
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
{ emit_if_match($0) }
' "$cfg" 2>/dev/null | sed -n '1p'
}

codex_config_current_provider() {
  cfg="${1:-$(codex_config_file)}"
  codex_config_root_string_value model_provider "$cfg"
}

codex_config_current_model() {
  cfg="${1:-$(codex_config_file)}"
  codex_config_root_string_value model "$cfg"
}

codex_config_current_base_url() {
  cfg="${1:-$(codex_config_file)}"
  provider="$(codex_config_current_provider "$cfg")"
  if [ -n "$provider" ]; then
    base="$(codex_config_section_string_value "$cfg" "model_providers.$provider" base_url)"
    [ -n "$base" ] && { printf '%s\n' "$base"; return 0; }
  fi
  codex_config_any_string_value base_url "$cfg"
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

codex_config_current_catalog_path() {
  cfg="${1:-$(codex_config_file)}"
  path="$(codex_config_root_string_value model_catalog_json "$cfg")"
  [ -n "$path" ] || path="$(codex_config_model_catalog_file)"
  printf '%s\n' "$path"
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

codex_config_ensure_hooks_feature_default_false() {
  codex_hooks_cfg="${1:-$(codex_config_file)}"
  mkdir -p "$(dirname "$codex_hooks_cfg")" || codex_die "无法创建 hooks 配置目录：$(dirname "$codex_hooks_cfg")"
  codex_hooks_input="$codex_hooks_cfg"
  [ -f "$codex_hooks_input" ] || codex_hooks_input="/dev/null"
  codex_hooks_tmp="$(codex_config_tmp_path "$codex_hooks_cfg")"
  awk '
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
    print "hooks = false"
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
    hooks_seen = 1
  }
  print
}
END {
  flush_features()
  if (!features_seen) {
    print ""
    print "[features]"
    print "hooks = false"
  }
}
' "$codex_hooks_input" > "$codex_hooks_tmp"
  codex_config_atomic_install_file "$codex_hooks_tmp" "$codex_hooks_cfg" 600 ||
    codex_die "无法写入 hooks 默认配置：$codex_hooks_cfg"
}

codex_config_strip_default_hook_blocks() {
  codex_hooks_cfg="$1"
  [ -f "$codex_hooks_cfg" ] || return 0
  codex_hooks_strip_rtk="$codex_hooks_cfg.strip-rtk.$$"
  codex_hooks_strip_context="$codex_hooks_cfg.strip-context.$$"
  codex_config_strip_managed_block \
    "# codex-for-tui-rtk-hook begin" \
    "# codex-for-tui-rtk-hook end" \
    "$codex_hooks_cfg" "$codex_hooks_strip_rtk"
  codex_config_strip_managed_block \
    "# codex-for-tui-context-hook begin" \
    "# codex-for-tui-context-hook end" \
    "$codex_hooks_strip_rtk" "$codex_hooks_strip_context"
  codex_config_atomic_install_file "$codex_hooks_strip_context" "$codex_hooks_cfg" 600 ||
    codex_die "无法清理默认 hooks 配置：$codex_hooks_cfg"
  rm -f "$codex_hooks_strip_rtk"
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
    printf '# codex-for-tui-managed-hooks end\n'
  } > "$codex_hooks_out"
  rm -f "$codex_hooks_strip"
  codex_config_atomic_install_file "$codex_hooks_out" "$codex_hooks_req" 644 ||
    return 1
}

codex_config_managed_hooks_available() {
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
  codex_config_ensure_hooks_feature_default_false "$codex_hooks_cfg"
  if codex_config_managed_hooks_enabled; then
    codex_config_strip_default_hook_blocks "$codex_hooks_cfg"
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

codex_config_set_catalog_path() {
  cfg="$1"
  catalog="$2"
  cfg_tmp="$(codex_config_tmp_path "$cfg")"
  catalog_esc="$(codex_toml_escape "$catalog")"
  mkdir -p "$(dirname "$cfg")"
  if [ -s "$cfg" ] && grep -q '^[[:space:]]*model_catalog_json[[:space:]]*=' "$cfg"; then
    sed "s#^[[:space:]]*model_catalog_json[[:space:]]*=.*#model_catalog_json = \"$catalog_esc\"#" "$cfg" > "$cfg_tmp"
  else
    [ -s "$cfg" ] && cat "$cfg" > "$cfg_tmp" || : > "$cfg_tmp"
    printf '\nmodel_catalog_json = "%s"\n' "$catalog_esc" >> "$cfg_tmp"
  fi
  codex_config_atomic_install_file "$cfg_tmp" "$cfg" 600 ||
    codex_die "无法写入 model_catalog_json 路径：$cfg"
}

codex_config_merge_common_and_runtime() {
  cfg="$1"
  out="$2"
  provider_id="$3"
  model_provider_line="$4"
  model_line="$5"
  catalog_line="$6"
  input="$cfg"
  [ -e "$input" ] || input="/dev/null"
  awk \
    -v provider="$provider_id" \
    -v model_provider_line="$model_provider_line" \
    -v model_line="$model_line" \
    -v catalog_line="$catalog_line" '
function section_name(line, s) {
  s = line
  sub(/^[[:space:]]*\[/, "", s)
  sub(/\][[:space:]]*($|#.*$)/, "", s)
  return s
}
function is_section(line) {
  return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*($|#)/
}
function emit_root_defaults() {
  if (root_done) {
    return
  }
  print model_provider_line
  print model_line
  if (!root_effort_seen) {
    print "model_reasoning_effort = \"medium\""
  }
  if (!root_compact_seen) {
    print "model_auto_compact_token_limit = 220000"
  }
  if (!root_service_tier_seen) {
    print "service_tier = \"default\""
  }
  print catalog_line
  if (!root_disable_storage_seen) {
    print "disable_response_storage = true"
  }
  root_done = 1
}
function flush_section_defaults() {
  if (section == "features") {
    if (!features_auto_seen) {
      print "auto_compaction = true"
    }
    if (!features_fast_seen) {
      print "fast_mode = true"
    }
    if (!features_goals_seen) {
      print "goals = true"
    }
    if (!features_hooks_seen) {
      print "hooks = false"
    }
  } else if (section == "tui") {
    if (!tui_status_line_seen) {
      print "status_line = [\"model-with-reasoning\", \"current-dir\", \"context-remaining\", \"used-tokens\", \"total-input-tokens\", \"total-output-tokens\", \"fast-mode\", \"task-progress\"]"
    }
    if (!tui_status_colors_seen) {
      print "status_line_use_colors = true"
    }
  }
}
{
  if (is_section($0)) {
    flush_section_defaults()
    s = section_name($0)
    if (s == "model_providers." provider || s == "model_providers." provider ".auth") {
      skipping = 1
      section = s
      next
    }
    skipping = 0
    if (!root_done) {
      emit_root_defaults()
    }
    section = s
    if (section == "features") {
      features_seen = 1
    } else if (section == "tui") {
      tui_seen = 1
    }
    print
    next
  }

  if (skipping) {
    if ($0 ~ /^[[:space:]]*($|#)/) {
      print
    }
    next
  }

  if (section == "") {
    if ($0 ~ /^[[:space:]]*model_provider[[:space:]]*=/) {
      next
    }
    if ($0 ~ /^[[:space:]]*model[[:space:]]*=/) {
      next
    }
    if ($0 ~ /^[[:space:]]*model_catalog_json[[:space:]]*=/) {
      next
    }
    if ($0 ~ /^[[:space:]]*model_reasoning_effort[[:space:]]*=/) {
      root_effort_seen = 1
    } else if ($0 ~ /^[[:space:]]*model_auto_compact_token_limit[[:space:]]*=/) {
      root_compact_seen = 1
    } else if ($0 ~ /^[[:space:]]*service_tier[[:space:]]*=/) {
      root_service_tier_seen = 1
    } else if ($0 ~ /^[[:space:]]*disable_response_storage[[:space:]]*=/) {
      root_disable_storage_seen = 1
    }
  } else if (section == "features") {
    if ($0 ~ /^[[:space:]]*auto_compaction[[:space:]]*=/) {
      features_auto_seen = 1
    } else if ($0 ~ /^[[:space:]]*fast_mode[[:space:]]*=/) {
      features_fast_seen = 1
    } else if ($0 ~ /^[[:space:]]*goals[[:space:]]*=/) {
      features_goals_seen = 1
    } else if ($0 ~ /^[[:space:]]*hooks[[:space:]]*=/) {
      features_hooks_seen = 1
    }
  } else if (section == "tui") {
    if ($0 ~ /^[[:space:]]*status_line[[:space:]]*=/) {
      tui_status_line_seen = 1
    } else if ($0 ~ /^[[:space:]]*status_line_use_colors[[:space:]]*=/) {
      tui_status_colors_seen = 1
    }
  }

  print
}
END {
  flush_section_defaults()
  if (!root_done) {
    emit_root_defaults()
  }
  if (!features_seen) {
    print ""
    print "[features]"
    print "auto_compaction = true"
    print "fast_mode = true"
    print "goals = true"
    print "hooks = false"
  }
  if (!tui_seen) {
    print ""
    print "[tui]"
    print "status_line = [\"model-with-reasoning\", \"current-dir\", \"context-remaining\", \"used-tokens\", \"total-input-tokens\", \"total-output-tokens\", \"fast-mode\", \"task-progress\"]"
    print "status_line_use_colors = true"
  }
}
' "$input" > "$out"
}

codex_config_write_third_party_config() {
  api_base="$1"
  api_key="$2"
  default_model="$3"
  models_file="$4"
  home_dir="$(codex_home)"
  cfg="$home_dir/config.toml"
  catalog="$home_dir/model_catalog.json"
  codex_config_validate_default_model "$default_model" "$models_file"
  helper="$(codex_config_write_auth_helper)"
  codex_config_write_auth_json "$api_key"
  codex_config_write_model_catalog "$models_file" "$default_model" "$catalog"
  api_base_esc="$(codex_toml_escape "$api_base")"
  model_esc="$(codex_toml_escape "$default_model")"
  provider_name_esc="$(codex_toml_escape "${CODEX_ZH_PROVIDER_NAME:-OpenAI}")"
  helper_esc="$(codex_toml_escape "$helper")"
  home_esc="$(codex_toml_escape "$home_dir")"
  catalog_esc="$(codex_toml_escape "$catalog")"
  config_tmp="$(codex_config_tmp_path "$cfg")"
  codex_config_clear_official_mode
  codex_config_merge_common_and_runtime \
    "$cfg" \
    "$config_tmp" \
    "$CODEX_ZH_PROVIDER_ID" \
    "model_provider = \"$CODEX_ZH_PROVIDER_ID\"" \
    "model = \"$model_esc\"" \
    "model_catalog_json = \"$catalog_esc\""

  cat >> "$config_tmp" <<EOF
[model_providers.$CODEX_ZH_PROVIDER_ID]
name = "$provider_name_esc"
base_url = "$api_base_esc"
wire_api = "responses"
requires_openai_auth = false

[model_providers.$CODEX_ZH_PROVIDER_ID.auth]
command = "$helper_esc"
args = []
timeout_ms = 5000
refresh_interval_ms = 300000
cwd = "$home_esc"
EOF
  codex_config_atomic_install_file "$config_tmp" "$cfg" 600 ||
    codex_die "无法写入 config.toml"
  codex_config_apply_full_permission "$cfg"
  codex_config_ensure_default_hooks
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

codex_config_choose_model() {
  models_file="$1"
  preferred_model="${2:-}"
  count="$(wc -l < "$models_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || codex_die "模型列表为空"
  default_choice="1"
  if [ -n "$preferred_model" ]; then
    preferred_choice="$(awk -v model="$preferred_model" '$0 == model { print NR; exit }' "$models_file")"
    [ -n "$preferred_choice" ] && default_choice="$preferred_choice"
  fi
  while :; do
    printf '%s\n' "可用模型：" >&2
    awk '{ printf "%2d. %s\n", NR, $0 }' "$models_file" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    choice="$(codex_config_tty_read "请选择默认模型编号" "$default_choice")"
    codex_config_is_back_choice "$choice" && return 1
    codex_config_is_exit_choice "$choice" && codex_config_exit_config_mode
    [ -n "$choice" ] || choice="$default_choice"
    case "$choice" in
      *[!0-9]*) codex_warn "请输入有效模型编号，或输入 b 返回。"; continue ;;
    esac
    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ] 2>/dev/null; then
      sed -n "${choice}p" "$models_file"
      return 0
    fi
    codex_warn "模型编号超出范围。"
  done
}

codex_config_prompt_third_party() {
  mode="${1:-new}"
  home_dir="$(codex_home)"
  cfg="$(codex_config_file)"
  work="$(codex_state_root)/configure"
  mkdir -p "$work"
  existing_base=""
  existing_key=""
  existing_model=""
  if [ "$mode" = "edit" ]; then
    [ -s "$cfg" ] || codex_die "缺少当前 config.toml，无法编辑配置"
    existing_base="$(codex_config_current_base_url "$cfg")"
    existing_key="$(codex_config_read_auth_key "$(codex_config_auth_file)" || true)"
    existing_model="$(codex_config_current_model "$cfg")"
  fi
  default_base="${CODEX_ZH_API_BASE:-$existing_base}"
  while :; do
    raw_base="$(codex_config_tty_read "API Base URL，例如 https://api.example.com/v1（b 返回，0 退出）" "$default_base")"
    codex_config_is_back_choice "$raw_base" && return 1
    codex_config_is_exit_choice "$raw_base" && codex_config_exit_config_mode
    codex_config_valid_api_base "$raw_base" && break
    codex_warn "API Base URL 无效，必须是 http(s) URL"
  done
  api_base="$(codex_config_normalize_api_base "$raw_base")"
  api_key="${CODEX_ZH_API_KEY:-}"
  if [ -z "$api_key" ]; then
    while :; do
      if [ "$mode" = "edit" ] && [ -n "$existing_key" ]; then
        api_key="$(codex_config_tty_read "API Key（留空保留当前，b 返回，0 退出）" "")"
        codex_config_is_back_choice "$api_key" && return 1
        codex_config_is_exit_choice "$api_key" && codex_config_exit_config_mode
        [ -n "$api_key" ] || api_key="$existing_key"
      else
        api_key="$(codex_config_tty_read "API Key（b 返回，0 退出）" "")"
        codex_config_is_back_choice "$api_key" && return 1
        codex_config_is_exit_choice "$api_key" && codex_config_exit_config_mode
      fi
      [ -n "$api_key" ] && break
      codex_warn "API Key 不能为空。"
    done
  fi
  [ -n "$api_key" ] || codex_die "API Key 不能为空"
  models_json="$work/models.json"
  models_err="$work/models.err"
  models_file="$work/models.txt"
  codex_info "请求模型列表：$api_base/models"
  if ! codex_config_fetch_models "$api_base" "$api_key" "$models_json" "$models_err"; then
    [ ! -s "$models_err" ] || sed -n '1,20p' "$models_err" >&2 || true
    codex_die "无法获取模型列表，未写入 config.toml"
  fi
  codex_config_parse_models "$models_json" > "$models_file"
  [ -s "$models_file" ] || codex_die "未解析到模型，未写入 config.toml"
  default_model="${CODEX_ZH_DEFAULT_MODEL:-}"
  if [ -z "$default_model" ]; then
    default_model="$(codex_config_choose_model "$models_file" "$existing_model")" || return 1
  fi
  codex_config_backup_current
  codex_config_write_third_party_config "$api_base" "$api_key" "$default_model" "$models_file"
  codex_info "已写入第三方配置：$home_dir/config.toml"
}

codex_config_refresh_models() {
  cfg="$(codex_config_file)"
  [ -s "$cfg" ] || codex_die "缺少 $cfg，请先显式配置"
  api_base="$(codex_config_current_base_url "$cfg")"
  [ -n "$api_base" ] || codex_die "config.toml 中没有 base_url，无法刷新第三方模型目录"
  api_key="$(codex_config_read_auth_key "$(codex_config_auth_file)" || true)"
  [ -n "$api_key" ] || codex_die "auth.json 中没有 OPENAI_API_KEY"
  default_model="$(codex_config_current_model "$cfg")"
  catalog="$(codex_config_current_catalog_path "$cfg")"
  work="$(codex_state_root)/refresh-models"
  mkdir -p "$work"
  models_json="$work/models.json"
  models_err="$work/models.err"
  models_file="$work/models.txt"
  codex_info "显式刷新模型目录：$api_base/models"
  if ! codex_config_fetch_models "$api_base" "$api_key" "$models_json" "$models_err"; then
    [ ! -s "$models_err" ] || sed -n '1,20p' "$models_err" >&2 || true
    codex_die "刷新失败，未修改当前配置"
  fi
  codex_config_parse_models "$models_json" > "$models_file"
  [ -s "$models_file" ] || codex_die "未解析到模型，未修改当前配置"
  codex_config_write_model_catalog "$models_file" "$default_model" "$catalog"
  codex_config_set_catalog_path "$cfg" "$catalog"
  codex_info "已刷新 model_catalog_json；保留当前 model 和 model_reasoning_effort"
}

codex_config_profiles_root() {
  printf '%s/config-profiles\n' "$(codex_home)"
}

codex_config_profile_current_file() {
  printf '%s/current\n' "$(codex_config_profiles_root)"
}

codex_config_profile_valid_name() {
  name="$1"
  [ -n "$name" ] || return 1
  case "$name" in
    "."|".."|*/*|*\\*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

codex_config_profile_dir() {
  name="$1"
  codex_config_profile_valid_name "$name" || codex_die "配置名称无效，只能使用字母、数字、点、下划线和短横线：$name"
  printf '%s/%s\n' "$(codex_config_profiles_root)" "$name"
}

codex_config_profile_current_name() {
  current_file="$(codex_config_profile_current_file)"
  [ -s "$current_file" ] || return 0
  name="$(sed -n '1p' "$current_file" 2>/dev/null | tr -d '\r')"
  codex_config_profile_valid_name "$name" || return 0
  [ -d "$(codex_config_profile_dir "$name")" ] || return 0
  printf '%s\n' "$name"
}

codex_config_profile_mark_current() {
  name="$1"
  codex_config_profile_valid_name "$name" || codex_die "配置名称无效，只能使用字母、数字、点、下划线和短横线：$name"
  root="$(codex_config_profiles_root)"
  current_file="$(codex_config_profile_current_file)"
  current_tmp="$(codex_config_tmp_path "$current_file")"
  mkdir -p "$root"
  printf '%s\n' "$name" > "$current_tmp" || codex_die "无法写入当前配置标记临时文件"
  codex_config_atomic_install_file "$current_tmp" "$current_file" 600 ||
    codex_die "无法写入当前配置标记"
}

codex_config_profile_clear_current() {
  codex_config_atomic_remove_file "$(codex_config_profile_current_file)" ||
    codex_die "无法清除当前配置标记"
}

codex_config_profile_list() {
  root="$(codex_config_profiles_root)"
  [ -d "$root" ] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

codex_config_profile_count() {
  codex_config_profile_list | wc -l | tr -d ' '
}

codex_config_files_same() {
  left="$1"
  right="$2"
  if [ -e "$left" ] || [ -e "$right" ]; then
    [ -s "$left" ] && [ -s "$right" ] || return 1
    cmp -s "$left" "$right"
    return $?
  fi
  return 0
}

codex_config_profile_matches_current() {
  name="$1"
  dir="$(codex_config_profile_dir "$name")"
  home_dir="$(codex_home)"
  codex_config_files_same "$home_dir/config.toml" "$dir/config.toml" || return 1
  codex_config_files_same "$home_dir/auth.json" "$dir/auth.json" || return 1
  current_catalog="$(codex_config_current_catalog_path "$home_dir/config.toml")"
  codex_config_files_same "$current_catalog" "$dir/model_catalog.json" || return 1
  codex_config_files_same "$(codex_config_official_marker_file)" "$dir/install-state/official-login-mode" || return 1
  return 0
}

codex_config_profile_is_dirty() {
  codex_config_has_runtime_config || return 1
  current="$(codex_config_profile_current_name)"
  [ -n "$current" ] || return 0
  codex_config_profile_matches_current "$current" || return 0
  return 1
}

codex_config_profile_status_label() {
  if ! codex_config_has_runtime_config; then
    printf '%s\n' "无当前配置"
    return 0
  fi
  current="$(codex_config_profile_current_name)"
  if [ -z "$current" ]; then
    printf '%s\n' "未保存当前配置"
  elif codex_config_profile_is_dirty; then
    printf '%s\n' "$current（未保存修改）"
  else
    printf '%s\n' "$current"
  fi
}

codex_config_default_profile_name() {
  current="$(codex_config_profile_current_name)"
  [ -n "$current" ] && { printf '%s\n' "$current"; return 0; }
  if [ "$(codex_config_profile_count)" = "0" ]; then
    printf '%s\n' "default"
  else
    stamp="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf '%s' "$$")"
    printf 'profile-%s\n' "$stamp"
  fi
}

codex_config_profile_save() {
  name="$1"
  cfg="$(codex_config_file)"
  [ -s "$cfg" ] || codex_die "缺少当前 config.toml，无法保存配置：$name"
  root="$(codex_config_profiles_root)"
  dest="$(codex_config_profile_dir "$name")"
  profile_tmp="$root/.tmp-$name-$$"
  rm -rf "$profile_tmp"
  mkdir -p "$profile_tmp"
  cp "$cfg" "$profile_tmp/config.toml"
  auth="$(codex_config_auth_file)"
  [ ! -s "$auth" ] || cp "$auth" "$profile_tmp/auth.json"
  catalog="$(codex_config_current_catalog_path "$cfg")"
  [ ! -s "$catalog" ] || cp "$catalog" "$profile_tmp/model_catalog.json"
  marker="$(codex_config_official_marker_file)"
  if [ -s "$marker" ]; then
    mkdir -p "$profile_tmp/install-state"
    cp "$marker" "$profile_tmp/install-state/official-login-mode"
    chmod 700 "$profile_tmp/install-state" 2>/dev/null || true
    chmod 600 "$profile_tmp/install-state/official-login-mode" 2>/dev/null || true
  fi
  for profile_file in config.toml auth.json model_catalog.json; do
    [ ! -e "$profile_tmp/$profile_file" ] || chmod 600 "$profile_tmp/$profile_file" 2>/dev/null || true
  done
  codex_config_atomic_replace_dir "$profile_tmp" "$dest" "profile-$name" ||
    codex_die "无法保存配置：$name"
  chmod 700 "$dest" 2>/dev/null || true
  codex_config_profile_mark_current "$name"
  codex_info "已保存配置：$name"
}

codex_config_profile_use() {
  name="$1"
  dir="$(codex_config_profile_dir "$name")"
  [ -s "$dir/config.toml" ] || codex_die "找不到配置：$name"
  home_dir="$(codex_home)"
  old_catalog="$(codex_config_current_catalog_path "$home_dir/config.toml" 2>/dev/null || true)"
  codex_config_backup_current
  codex_ensure_private_dir "$home_dir"
  tmp_cfg="$(codex_config_tmp_path "$home_dir/config.toml")"
  cp "$dir/config.toml" "$tmp_cfg"
  codex_config_atomic_install_file "$tmp_cfg" "$home_dir/config.toml" 600 ||
    codex_die "无法切换 config.toml"

  if [ -s "$dir/auth.json" ]; then
    tmp_auth="$(codex_config_tmp_path "$home_dir/auth.json")"
    cp "$dir/auth.json" "$tmp_auth"
    codex_config_atomic_install_file "$tmp_auth" "$home_dir/auth.json" 600 ||
      codex_die "无法切换 auth.json"
  else
    codex_config_atomic_remove_file "$home_dir/auth.json" ||
      codex_die "无法移除旧 auth.json"
  fi

  if [ -s "$dir/model_catalog.json" ]; then
    catalog_target="$(codex_config_current_catalog_path "$home_dir/config.toml")"
    [ -n "$catalog_target" ] || catalog_target="$home_dir/model_catalog.json"
    catalog_dir="$(dirname "$catalog_target")"
    if mkdir -p "$catalog_dir" 2>/dev/null; then
      tmp_catalog="$(codex_config_tmp_path "$catalog_target")"
      if cp "$dir/model_catalog.json" "$tmp_catalog" 2>/dev/null &&
        codex_config_atomic_install_file "$tmp_catalog" "$catalog_target" 600 2>/dev/null; then
        :
      else
        rm -f "$tmp_catalog" 2>/dev/null || true
        catalog_target="$home_dir/model_catalog.json"
        tmp_catalog="$(codex_config_tmp_path "$catalog_target")"
        cp "$dir/model_catalog.json" "$tmp_catalog"
        codex_config_atomic_install_file "$tmp_catalog" "$catalog_target" 600 ||
          codex_die "无法切换 model_catalog.json"
        codex_config_set_catalog_path "$home_dir/config.toml" "$catalog_target"
      fi
    else
      catalog_target="$home_dir/model_catalog.json"
      tmp_catalog="$(codex_config_tmp_path "$catalog_target")"
      cp "$dir/model_catalog.json" "$tmp_catalog"
      codex_config_atomic_install_file "$tmp_catalog" "$catalog_target" 600 ||
        codex_die "无法切换 model_catalog.json"
      codex_config_set_catalog_path "$home_dir/config.toml" "$catalog_target"
    fi
  else
    catalog_target="$(codex_config_current_catalog_path "$home_dir/config.toml")"
    case "$catalog_target" in
      "$home_dir"/*) codex_config_atomic_remove_file "$catalog_target" || codex_die "无法移除旧 model_catalog.json" ;;
    esac
    if [ -n "$old_catalog" ] && [ "$old_catalog" != "$catalog_target" ]; then
      case "$old_catalog" in
        "$home_dir"/*) codex_config_atomic_remove_file "$old_catalog" || codex_die "无法移除旧 model_catalog.json" ;;
      esac
    fi
  fi

  profile_marker="$dir/install-state/official-login-mode"
  runtime_marker="$(codex_config_official_marker_file)"
  if [ -s "$profile_marker" ]; then
    mkdir -p "$(dirname "$runtime_marker")"
    tmp_marker="$(codex_config_tmp_path "$runtime_marker")"
    cp "$profile_marker" "$tmp_marker"
    codex_config_atomic_install_file "$tmp_marker" "$runtime_marker" 600 ||
      codex_die "无法切换官方登录标记"
  else
    codex_config_clear_official_mode
  fi
  codex_config_apply_full_permission "$home_dir/config.toml"
  codex_config_ensure_default_hooks
  codex_config_profile_mark_current "$name"
  codex_info "已切换配置：$name"
}

codex_config_profile_new() {
  name="$1"
  codex_config_profile_valid_name "$name" || codex_die "配置名称无效，只能使用字母、数字、点、下划线和短横线：$name"
  codex_config_prompt_third_party
  codex_config_profile_save "$name"
}

codex_config_prompt_profile_name() {
  prompt="$1"
  default="${2:-}"
  CODEX_CONFIG_PROFILE_NAME=""
  while :; do
    name="$(codex_config_tty_read "$prompt（b 返回，0 退出）" "$default")"
    case "$name" in
      b|B|back|BACK|返回) return 1 ;;
      0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
    esac
    if codex_config_profile_valid_name "$name"; then
      CODEX_CONFIG_PROFILE_NAME="$name"
      return 0
    fi
    codex_warn "配置名称无效，只能使用字母、数字、点、下划线和短横线。"
  done
}

codex_config_profile_save_interactive() {
  default="$(codex_config_default_profile_name)"
  codex_config_prompt_profile_name "请输入配置名称" "$default" || return 1
  name="$CODEX_CONFIG_PROFILE_NAME"
  dest="$(codex_config_profile_dir "$name")"
  if [ -e "$dest" ] && ! codex_config_tty_confirm "配置已存在，是否覆盖？" "y"; then
    codex_warn "已取消保存配置"
    return 1
  fi
  codex_config_profile_save "$name"
}

codex_config_profile_choose_name() {
  prompt="${1:-请选择配置编号}"
  work="$(codex_state_root)/profile-menu"
  mkdir -p "$work"
  profiles_file="$work/profiles.txt"
  CODEX_CONFIG_SELECTED_PROFILE=""
  while :; do
    codex_config_profile_list > "$profiles_file"
    if [ ! -s "$profiles_file" ]; then
      codex_warn "没有已保存配置；请先新建或保存当前配置。"
      return 1
    fi
    printf '%s\n' "已保存配置：" >&2
    awk '{ printf "%2d. %s\n", NR, $0 }' "$profiles_file" >&2
    printf '%s\n' "b. 返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    count="$(wc -l < "$profiles_file" | tr -d ' ')"
    choice="$(codex_config_tty_read "$prompt" "b")"
    case "$choice" in
      b|B|back|BACK|返回) return 1 ;;
      0|q|Q|quit|QUIT|退出) codex_config_exit_config_mode ;;
      *[!0-9]*|"") codex_warn "请输入有效编号，或输入 b 返回。"; continue ;;
    esac
    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ] 2>/dev/null; then
      CODEX_CONFIG_SELECTED_PROFILE="$(sed -n "${choice}p" "$profiles_file")"
      return 0
    fi
    codex_warn "配置编号超出范围。"
  done
}

codex_config_confirm_save_dirty_before() {
  reason="${1:-继续操作}"
  codex_config_profile_is_dirty || return 0
  while :; do
    current="$(codex_config_profile_current_name)"
    printf '%s\n' "当前配置有未保存修改，$reason 前请选择：" >&2
    if [ -n "$current" ]; then
      printf '%s\n' "1. 保存到当前配置：$current（推荐）" >&2
    else
      printf '%s\n' "1. 保存为配置档（推荐）" >&2
    fi
    printf '%s\n' "2. 另存为新配置" >&2
    printf '%s\n' "3. 不保存，继续" >&2
    printf '%s\n' "b. 取消并返回上一层" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    choice="$(codex_config_tty_read "请输入选项编号" "1")"
    case "$choice" in
      1|"")
        if [ -n "$current" ]; then
          codex_config_profile_save "$current" && return 0
        else
          codex_config_profile_save_interactive && return 0
        fi
        ;;
      2)
        codex_config_profile_save_interactive && return 0
        ;;
      3)
        return 0
        ;;
      b|B|back|BACK|返回)
        return 1
        ;;
      0|q|Q|quit|QUIT|退出)
        codex_config_exit_config_mode
        ;;
      *)
        codex_warn "请输入 1、2、3、b 或 0。"
        ;;
    esac
  done
}

codex_config_prompt_save_after_write() {
  default="${1:-$(codex_config_default_profile_name)}"
  while :; do
    printf '%s\n' "是否保存为配置档？" >&2
    printf '%s\n' "1. 保存为 $default（推荐）" >&2
    printf '%s\n' "2. 输入新名称保存" >&2
    printf '%s\n' "3. 暂不保存，保留为当前未保存配置" >&2
    printf '%s\n' "b. 返回菜单" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    choice="$(codex_config_tty_read "请输入选项编号" "1")"
    case "$choice" in
      1|"")
        if [ -e "$(codex_config_profile_dir "$default")" ] && ! codex_config_tty_confirm "配置 $default 已存在，是否覆盖？" "y"; then
          continue
        fi
        codex_config_profile_save "$default"
        return 0
        ;;
      2)
        codex_config_profile_save_interactive
        return 0
        ;;
      3|b|B|back|BACK|返回)
        codex_config_profile_clear_current
        codex_warn "当前配置尚未保存；切换或退出前会再次提示保存。"
        return 0
        ;;
      0|q|Q|quit|QUIT|退出)
        codex_config_exit_config_mode
        ;;
      *)
        codex_warn "请输入 1、2、3、b 或 0。"
        ;;
    esac
  done
}

codex_config_profile_choose_use() {
  codex_config_profile_choose_name "请选择要切换的配置编号" || return 1
  CODEX_CONFIG_PROFILE_TO_USE="$CODEX_CONFIG_SELECTED_PROFILE"
  codex_config_confirm_save_dirty_before "切换配置" || return 1
  codex_config_profile_use "$CODEX_CONFIG_PROFILE_TO_USE"
}

codex_config_profile_delete_interactive() {
  codex_config_profile_choose_name "请选择要删除的配置编号" || return 1
  CODEX_CONFIG_PROFILE_TO_DELETE="$CODEX_CONFIG_SELECTED_PROFILE"
  dir="$(codex_config_profile_dir "$CODEX_CONFIG_PROFILE_TO_DELETE")"
  [ -d "$dir" ] || { codex_warn "配置不存在：$CODEX_CONFIG_PROFILE_TO_DELETE"; return 1; }
  if ! codex_config_tty_confirm "确认删除配置 $CODEX_CONFIG_PROFILE_TO_DELETE？" "n"; then
    codex_warn "已取消删除。"
    return 1
  fi
  codex_config_backup_file "$dir" "profile-$CODEX_CONFIG_PROFILE_TO_DELETE" ||
    codex_die "无法备份待删除配置：$CODEX_CONFIG_PROFILE_TO_DELETE"
  rm -rf "$dir"
  current="$(codex_config_profile_current_name)"
  [ "$current" = "$CODEX_CONFIG_PROFILE_TO_DELETE" ] && codex_config_profile_clear_current
  codex_info "已删除配置：$CODEX_CONFIG_PROFILE_TO_DELETE"
}

codex_config_profile_summary_from_dir() {
  label="$1"
  dir="$2"
  cfg="$dir/config.toml"
  auth="$dir/auth.json"
  catalog="$dir/model_catalog.json"
  printf '%s\n' "[$label]" >&2
  if [ ! -s "$cfg" ]; then
    printf '%s\n' "  config.toml: 缺失" >&2
    return 0
  fi
  printf '%s\n' "  model: $(codex_config_current_model "$cfg")" >&2
  printf '%s\n' "  base_url: $(codex_config_current_base_url "$cfg")" >&2
  if codex_config_is_full_permission "$cfg"; then
    printf '%s\n' "  full_permission: yes" >&2
  else
    printf '%s\n' "  full_permission: no" >&2
  fi
  [ -s "$dir/install-state/official-login-mode" ] && printf '%s\n' "  official_login_mode: yes" >&2 || printf '%s\n' "  official_login_mode: no" >&2
  [ -s "$auth" ] && printf '%s\n' "  auth.json: 已保存（key 不显示）" >&2 || printf '%s\n' "  auth.json: 缺失" >&2
  [ -s "$catalog" ] && printf '%s\n' "  model_catalog.json: 已保存" >&2 || printf '%s\n' "  model_catalog.json: 缺失" >&2
}

codex_config_current_summary() {
  home_dir="$(codex_home)"
  tmp_dir="$home_dir"
  printf '%s\n' "当前配置：$(codex_config_profile_status_label)" >&2
  codex_config_profile_summary_from_dir "current" "$tmp_dir"
}

codex_config_profile_view_interactive() {
  codex_config_current_summary
  printf '%s\n' "" >&2
  printf '%s\n' "已保存配置：" >&2
  if codex_config_profile_list | sed 's/^/  - /' >&2; then
    :
  fi
  printf '%s\n' "" >&2
  codex_config_profile_choose_name "输入编号查看详情，或 b 返回" || return 0
  CODEX_CONFIG_PROFILE_TO_VIEW="$CODEX_CONFIG_SELECTED_PROFILE"
  codex_config_profile_summary_from_dir "$CODEX_CONFIG_PROFILE_TO_VIEW" "$(codex_config_profile_dir "$CODEX_CONFIG_PROFILE_TO_VIEW")"
}

codex_config_menu_migrate_existing() {
  codex_config_has_runtime_config || return 0
  root="$(codex_config_profiles_root)"
  mkdir -p "$root"
  current="$(codex_config_profile_current_name)"
  [ -n "$current" ] && return 0
  if [ "$(codex_config_profile_count)" = "0" ]; then
    printf '%s\n' "检测到当前已有配置，但还没有保存档。" >&2
    while :; do
      printf '%s\n' "1. 保存为 default（推荐）" >&2
      printf '%s\n' "2. 输入名称保存" >&2
      printf '%s\n' "3. 暂不保存" >&2
      choice="$(codex_config_tty_read "请输入选项编号" "1")"
      case "$choice" in
        1|"") codex_config_profile_save default; return 0 ;;
        2) codex_config_profile_save_interactive; return 0 ;;
        3) codex_warn "当前配置尚未保存；切换或退出前会再次提示保存。"; return 0 ;;
        *) codex_warn "请输入 1、2 或 3。" ;;
      esac
    done
  fi
  for name in $(codex_config_profile_list); do
    if codex_config_profile_matches_current "$name"; then
      codex_config_profile_mark_current "$name"
      return 0
    fi
  done
  codex_warn "当前配置未匹配到已保存配置；切换或退出前会提示保存。"
}

codex_config_menu_new() {
  if ( codex_config_prompt_third_party new ); then
    default="$(codex_config_default_profile_name)"
    codex_config_prompt_save_after_write "$default"
  else
    codex_warn "新建配置未完成，已返回配置模式。"
  fi
}

codex_config_menu_edit() {
  [ -s "$(codex_config_file)" ] || { codex_warn "缺少当前 config.toml，无法编辑；请先新建配置。"; return 1; }
  current="$(codex_config_profile_current_name)"
  if ( codex_config_prompt_third_party edit ); then
    default="${current:-$(codex_config_default_profile_name)}"
    codex_config_prompt_save_after_write "$default"
  else
    codex_warn "编辑配置未完成，已返回配置模式。"
  fi
}

codex_config_menu_refresh_models() {
  if ( codex_config_backup_current; codex_config_refresh_models ); then
    current="$(codex_config_profile_current_name)"
    [ -z "$current" ] || codex_config_profile_save "$current" || true
    codex_info "模型目录刷新完成。"
  else
    codex_warn "模型目录刷新失败，已返回配置模式。"
  fi
}

codex_config_menu_repair_full_permission() {
  if ( codex_config_repair_full_permission ); then
    current="$(codex_config_profile_current_name)"
    [ -z "$current" ] || codex_config_profile_save "$current" || true
  else
    codex_warn "全权限授权修复失败，已返回配置模式。"
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

codex_config_menu() {
  codex_config_menu_migrate_existing
  while :; do
    printf '%s\n' "" >&2
    printf '%s\n' "Codex 配置模式" >&2
    printf '%s\n' "当前配置：$(codex_config_profile_status_label)" >&2
    printf '%s\n' "1. 新建配置" >&2
    printf '%s\n' "2. 选择配置" >&2
    printf '%s\n' "3. 编辑当前配置" >&2
    printf '%s\n' "4. 查看配置" >&2
    printf '%s\n' "5. 删除配置" >&2
    printf '%s\n' "6. 保存当前配置" >&2
    printf '%s\n' "7. 刷新当前模型目录" >&2
    printf '%s\n' "8. 修复全权限授权" >&2
    printf '%s\n' "9. 返回并启动 Codex" >&2
    printf '%s\n' "0. 退出，不启动 Codex" >&2
    choice="$(codex_config_tty_read "请输入选项编号" "9")"
    case "$choice" in
      1)
        codex_config_menu_new
        ;;
      2)
        codex_config_profile_choose_use || true
        ;;
      3)
        codex_config_menu_edit || true
        ;;
      4)
        codex_config_profile_view_interactive || true
        ;;
      5)
        codex_config_profile_delete_interactive || true
        ;;
      6)
        if codex_config_has_runtime_config; then
          codex_config_profile_save_interactive || true
        else
          codex_warn "当前没有可保存的配置；请先新建配置。"
        fi
        ;;
      7)
        codex_config_menu_refresh_models
        ;;
      8)
        codex_config_menu_repair_full_permission
        ;;
      9)
        codex_config_confirm_save_dirty_before "返回启动 Codex" || continue
        return 0
        ;;
      0|q|Q|quit|QUIT|退出)
        codex_config_confirm_save_dirty_before "退出配置模式" || continue
        codex_config_exit_config_mode
        ;;
      b|B|back|BACK|返回)
        codex_config_confirm_save_dirty_before "返回启动 Codex" || continue
        return 0
        ;;
      *)
        codex_warn "请输入 0 到 9，或输入 b 返回。"
        ;;
    esac
  done
}
