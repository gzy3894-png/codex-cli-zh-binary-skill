# shellcheck shell=sh
[ "${CODEX_ZH_CONFIG_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_CONFIG_LOADED=1

codex_config_file() {
  printf '%s/config.toml\n' "$(codex_home)"
}

codex_config_official_marker_file() {
  printf '%s/official-login-mode\n' "$(codex_state_root)"
}

codex_config_mark_official_mode() {
  marker="$(codex_config_official_marker_file)"
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "official-login" > "$marker"
  chmod 600 "$marker" 2>/dev/null || true
}

codex_config_clear_official_mode() {
  rm -f "$(codex_config_official_marker_file)" 2>/dev/null || true
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
  tmp="$auth_file.tmp"
  {
    printf '{\n'
    printf '  "OPENAI_API_KEY": "%s"\n' "$(codex_json_escape "$api_key")"
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$auth_file"
  chmod 600 "$auth_file" 2>/dev/null || true
}

codex_config_write_auth_helper() {
  home_dir="$(codex_home)"
  helper_dir="$home_dir/bin"
  helper="$helper_dir/provider-api-key"
  codex_ensure_private_dir "$home_dir"
  mkdir -p "$helper_dir"
  cat > "$helper" <<'EOF'
#!/usr/bin/env sh
auth_file="${CODEX_HOME:-$HOME/.codex}/auth.json"
sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$auth_file" | sed -n '1p'
EOF
  chmod 700 "$helper"
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
  tmp="$out_json.tmp"
  dedup="$out_json.models.tmp"
  mkdir -p "$(dirname "$out_json")"
  if [ -s "$models_file" ]; then
    awk 'NF && !seen[$0]++ { print }' "$models_file" > "$dedup"
  elif [ -n "$default_model" ]; then
    printf '%s\n' "$default_model" > "$dedup"
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
      "default_verbosity": "medium",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text",
      "input_modalities": ["text", "image"],
      "supports_image_detail_original": true,
      "truncation_policy": {"mode": "tokens", "limit": 10000},
      "supports_parallel_tool_calls": true,
      "context_window": 272000,
      "max_context_window": 272000,
      "auto_compact_token_limit": 120000,
      "reasoning_summary_format": "experimental",
      "default_reasoning_summary": "none",
      "slug": "$model_esc",
      "display_name": "$name_esc",
      "description": "$name_esc",
      "default_reasoning_level": "medium",
      "supported_reasoning_levels": ["minimal", "low", "medium", "high"],
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
    done < "$dedup"
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$out_json"
  chmod 600 "$out_json" 2>/dev/null || true
  rm -f "$dedup"
}

codex_config_current_model() {
  cfg="${1:-$(codex_config_file)}"
  sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$cfg" 2>/dev/null | sed -n '1p'
}

codex_config_current_base_url() {
  cfg="${1:-$(codex_config_file)}"
  sed -n 's/^[[:space:]]*base_url[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$cfg" 2>/dev/null | sed -n '1p'
}

codex_config_current_catalog_path() {
  cfg="${1:-$(codex_config_file)}"
  path="$(sed -n 's/^[[:space:]]*model_catalog_json[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$cfg" 2>/dev/null | sed -n '1p')"
  [ -n "$path" ] || path="$(codex_config_model_catalog_file)"
  printf '%s\n' "$path"
}

codex_config_set_catalog_path() {
  cfg="$1"
  catalog="$2"
  tmp="$cfg.tmp"
  catalog_esc="$(codex_toml_escape "$catalog")"
  if [ -s "$cfg" ] && grep -q '^[[:space:]]*model_catalog_json[[:space:]]*=' "$cfg"; then
    sed "s#^[[:space:]]*model_catalog_json[[:space:]]*=.*#model_catalog_json = \"$catalog_esc\"#" "$cfg" > "$tmp"
  else
    [ -s "$cfg" ] && cat "$cfg" > "$tmp" || : > "$tmp"
    printf '\nmodel_catalog_json = "%s"\n' "$catalog_esc" >> "$tmp"
  fi
  mv "$tmp" "$cfg"
  chmod 600 "$cfg" 2>/dev/null || true
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
  helper_esc="$(codex_toml_escape "$helper")"
  home_esc="$(codex_toml_escape "$home_dir")"
  catalog_esc="$(codex_toml_escape "$catalog")"
  tmp="$cfg.tmp"
  codex_config_clear_official_mode
  cat > "$tmp" <<EOF
model_provider = "$CODEX_ZH_PROVIDER_ID"
model = "$model_esc"
model_reasoning_effort = "medium"
model_auto_compact_token_limit = 120000
model_catalog_json = "$catalog_esc"
disable_response_storage = true

[features]
auto_compaction = true
hooks = false

[model_providers.$CODEX_ZH_PROVIDER_ID]
name = "$CODEX_ZH_PROVIDER_ID"
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
  mv "$tmp" "$cfg"
  chmod 600 "$cfg" 2>/dev/null || true
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

codex_config_choose_model() {
  models_file="$1"
  count="$(wc -l < "$models_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || codex_die "模型列表为空"
  printf '%s\n' "可用模型：" >&2
  awk '{ printf "%2d. %s\n", NR, $0 }' "$models_file" >&2
  choice="$(codex_config_tty_read "请选择默认模型编号" "1")"
  case "$choice" in *[!0-9]*|"") choice=1 ;; esac
  [ "$choice" -ge 1 ] 2>/dev/null || choice=1
  [ "$choice" -le "$count" ] 2>/dev/null || choice=1
  sed -n "${choice}p" "$models_file"
}

codex_config_prompt_third_party() {
  home_dir="$(codex_home)"
  work="$(codex_state_root)/configure"
  mkdir -p "$work"
  while :; do
    raw_base="$(codex_config_tty_read "API Base URL，例如 https://api.example.com/v1" "${CODEX_ZH_API_BASE:-}")"
    codex_config_valid_api_base "$raw_base" && break
    codex_warn "API Base URL 无效，必须是 http(s) URL"
  done
  api_base="$(codex_config_normalize_api_base "$raw_base")"
  api_key="${CODEX_ZH_API_KEY:-}"
  [ -n "$api_key" ] || api_key="$(codex_config_tty_read "API Key" "")"
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
  [ -n "$default_model" ] || default_model="$(codex_config_choose_model "$models_file")"
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
