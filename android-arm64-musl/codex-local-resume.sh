#!/usr/bin/env sh
set -eu

VERSION="${CODEX_ZH_VERSION:-0.142.4}"
TARGET="${CODEX_ZH_TARGET:-aarch64-unknown-linux-musl}"
INSTALL_NAME="${CODEX_ZH_INSTALL_NAME:-codex}"
PROVIDER_ID="${CODEX_ZH_PROVIDER_ID:-custom}"
INSTALL_DIR="${CODEX_ZH_INSTALL_DIR:-}"
CODEX_HOME="${CODEX_HOME:-}"
STATE_DIR=""
CONFIGS_DIR=""
LAST_PROFILE_FILE=""
REAL_BIN=""
RESUME_SCRIPT=""
LAUNCHER=""
WRAPPER=""
SKIP_RUN="${CODEX_ZH_SKIP_RUN:-0}"
MODEL_CATALOG_BASENAME="model_catalog.json"
LEGACY_MODEL_CATALOG_BASENAME="model-catalog.json"

info() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
lower() { tr '[:upper:]' '[:lower:]'; }
is_root() { [ "${USER:-}" = "root" ] || [ "${UID:-}" = "0" ] || [ -w /etc/profile.d ]; }
looks_like_url() {
  case "$1" in
    http://*|https://*|*://*) return 0 ;;
    *) return 1 ;;
  esac
}
tty_available() {
  [ "${CODEX_ZH_FORCE_STDIN:-0}" = "1" ] && return 1
  [ -r /dev/tty ] && [ -w /dev/tty ] && { : < /dev/tty; } 2>/dev/null
}

clear_screen() {
  if tty_available && [ "${TERM:-}" != "dumb" ]; then
    printf '\033[H\033[2J' > /dev/tty
  else
    printf '\n\n' >&2
  fi
}

section_title() {
  clear_screen
  printf '\n%s\n' "======== $1 ========" >&2
  printf '\n' >&2
}

exit_for_later() {
  printf '\n%s\n' "已暂停配置。稍后重新打开 App，或运行 codex / codex-local-resume 继续。" >&2
  exit 130
}

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

profile_slug() {
  slug="$(printf '%s' "$1" | lower | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  [ -n "$slug" ] || slug="api"
  printf '%s' "$slug"
}

profile_label() {
  profile_dir="$1"
  if [ -s "$profile_dir/name" ]; then
    sed -n '1p' "$profile_dir/name"
  else
    basename "$profile_dir"
  fi
}

profile_mode() {
  profile_dir="$1"
  sed -n '1p' "$profile_dir/setup-mode" 2>/dev/null || true
}

profile_api_base() {
  profile_dir="$1"
  api_base="$(sed -n '1p' "$profile_dir/api-base" 2>/dev/null || true)"
  [ -n "$api_base" ] || api_base="$(sed -n 's/^[[:space:]]*base_url[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$profile_dir/config.toml" | sed -n '1p')"
  printf '%s' "$api_base"
}

profile_default_model() {
  profile_dir="$1"
  default_model="$(sed -n '1p' "$profile_dir/default-model" 2>/dev/null || true)"
  [ -n "$default_model" ] || default_model="$(sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$profile_dir/config.toml" | sed -n '1p')"
  printf '%s' "$default_model"
}

model_catalog_path() {
  printf '%s/%s\n' "$1" "$MODEL_CATALOG_BASENAME"
}

legacy_model_catalog_path() {
  printf '%s/%s\n' "$1" "$LEGACY_MODEL_CATALOG_BASENAME"
}

remove_model_catalog_files() {
  dir="$1"
  rm -f "$(model_catalog_path "$dir")" "$(legacy_model_catalog_path "$dir")"
}

copy_model_catalog_file() {
  src_dir="$1"
  dst_dir="$2"
  src_file=""

  if [ -s "$(model_catalog_path "$src_dir")" ]; then
    src_file="$(model_catalog_path "$src_dir")"
  elif [ -s "$(legacy_model_catalog_path "$src_dir")" ]; then
    src_file="$(legacy_model_catalog_path "$src_dir")"
  fi

  [ -n "$src_file" ] || return 0
  cp "$src_file" "$(model_catalog_path "$dst_dir")"
  rm -f "$(legacy_model_catalog_path "$dst_dir")"
}

current_profile_dir() {
  slug="$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)"
  [ -n "$slug" ] || return 1
  profile_dir="$CONFIGS_DIR/$slug"
  [ -d "$profile_dir" ] || return 1
  printf '%s\n' "$profile_dir"
}

profile_models_source_file() {
  profile_dir="$1"
  if [ -s "$profile_dir/models.txt" ]; then
    printf '%s\n' "$profile_dir/models.txt"
    return 0
  fi
  if [ -s "$profile_dir/enabled-models.txt" ]; then
    printf '%s\n' "$profile_dir/enabled-models.txt"
    return 0
  fi
  return 1
}

ensure_third_party_profile_usable() {
  profile_dir="$1"
  [ -d "$profile_dir" ] || return 1
  [ "$(profile_mode "$profile_dir")" = "third_party" ] || return 0

  api_base="$(profile_api_base "$profile_dir")"
  api_key="$(read_auth_api_key "$profile_dir/auth.json" 2>/dev/null || true)"
  models_source="$(profile_models_source_file "$profile_dir" 2>/dev/null || true)"
  default_model="$(profile_default_model "$profile_dir")"

  [ -n "$api_base" ] || return 1
  [ -n "$api_key" ] || return 1
  [ -n "$models_source" ] || return 1
  [ -n "$default_model" ] || default_model="$(sed -n '1p' "$models_source" 2>/dev/null || true)"
  [ -n "$default_model" ] || return 1

  if [ ! -s "$profile_dir/models.txt" ]; then
    cp "$models_source" "$profile_dir/models.txt"
    models_source="$profile_dir/models.txt"
  fi
  if [ ! -s "$profile_dir/enabled-models.txt" ]; then
    cp "$models_source" "$profile_dir/enabled-models.txt"
  fi
  if ! list_has_line "$default_model" "$profile_dir/models.txt"; then
    printf '%s\n' "$default_model" >> "$profile_dir/models.txt"
  fi
  if ! list_has_line "$default_model" "$profile_dir/enabled-models.txt"; then
    printf '%s\n' "$default_model" >> "$profile_dir/enabled-models.txt"
  fi

  needs_rebuild=0
  [ -s "$profile_dir/config.toml" ] || needs_rebuild=1
  [ -s "$(model_catalog_path "$profile_dir")" ] || [ -s "$(legacy_model_catalog_path "$profile_dir")" ] || needs_rebuild=1
  [ -x "$profile_dir/bin/provider-api-key" ] || needs_rebuild=1
  if [ "$needs_rebuild" = "1" ]; then
    write_codex_config "$api_base" "$api_key" "$default_model" "$profile_dir/models.txt" "$profile_dir"
  fi

  chmod 700 "$profile_dir" "$profile_dir/bin" 2>/dev/null || true
  chmod 600 "$profile_dir/config.toml" "$profile_dir/auth.json" "$profile_dir/models.txt" "$profile_dir/enabled-models.txt" "$(model_catalog_path "$profile_dir")" 2>/dev/null || true
  chmod 700 "$profile_dir/bin/provider-api-key" 2>/dev/null || true
  return 0
}

profile_is_usable() {
  profile_dir="$1"
  case "$(profile_mode "$profile_dir")" in
    official)
      [ -s "$profile_dir/setup-mode" ]
      ;;
    third_party)
      ensure_third_party_profile_usable "$profile_dir"
      ;;
    *)
      return 1
      ;;
  esac
}

list_has_line() {
  value="$1"
  list_file="$2"
  [ -n "$value" ] || return 1
  [ -s "$list_file" ] || return 1
  grep -Fx "$value" "$list_file" >/dev/null 2>&1
}

tty_read() {
  prompt="$1"
  default="${2:-}"
  if tty_available; then
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
    else
      printf '%s: ' "$prompt" > /dev/tty
    fi
    IFS= read -r ans < /dev/tty || ans=""
  else
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" >&2
    else
      printf '%s: ' "$prompt" >&2
    fi
    IFS= read -r ans || ans=""
  fi
  [ -n "$ans" ] || ans="$default"
  printf '%s' "$ans"
}

tty_read_api_key() {
  prompt="$1"
  if [ "${CODEX_ZH_HIDE_API_KEY:-0}" = "1" ] && tty_available; then
    printf '%s（输入时不显示，粘贴后按回车）: ' "$prompt" > /dev/tty
    old_stty="$(stty -g < /dev/tty 2>/dev/null || true)"
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r ans < /dev/tty || ans=""
    [ -z "$old_stty" ] || stty "$old_stty" < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
  else
    ans="$(tty_read "$prompt（默认明文显示；如需隐藏可设置 CODEX_ZH_HIDE_API_KEY=1）" "")"
  fi
  printf '%s' "$ans"
}

menu_read() {
  prompt="$1"
  default="$2"
  allowed="$3"
  hint="${4:-}"
  while :; do
    ans="$(tty_read "$prompt" "$default")"
    ans_lc="$(printf '%s' "$ans" | lower)"
    for item in $allowed; do
      [ "$ans_lc" = "$item" ] && { printf '%s' "$ans_lc"; return 0; }
    done
    if looks_like_url "$ans_lc"; then
      warn "你可能把 API Base URL 粘到了菜单编号处；请先选择对应编号，再填写 URL。"
    else
      warn "无效选项：$ans"
    fi
    [ -z "$hint" ] || printf '%s\n' "$hint" >&2
    printf '\n' >&2
  done
}

normalize_api_base() {
  printf '%s' "$1" | sed 's/[[:space:]]//g; s#/*$##' | awk '
    /\/v1$/ { print; next }
    { print $0 "/v1" }
  '
}

valid_api_base_input() {
  cleaned="$(printf '%s' "$1" | sed 's/[[:space:]]//g')"
  case "$cleaned" in
    http://?*|https://?*) ;;
    *) return 1 ;;
  esac
  host_path="$(printf '%s' "$cleaned" | sed 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##')"
  host="$(printf '%s' "$host_path" | sed 's#[/?#].*##')"
  [ -n "$host" ] && [ "$host" != "$host_path/" ]
}

parse_models() {
  json_file="$1"
  if have jq; then
    jq -r '.data[]?.id // empty' "$json_file" 2>/dev/null | sed '/^$/d'
  else
    sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json_file" | sed '/^$/d'
  fi
}

fetch_models() {
  api_base="$1"
  api_key="$2"
  out_json="$3"
  err_file="$4"

  if have curl; then
    curl -fsS --http1.1 \
      --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 60 \
      -H "Authorization: Bearer $api_key" \
      -H "Accept: application/json" \
      "$api_base/models" \
      -o "$out_json" \
      2>"$err_file"
  elif have wget; then
    wget -O "$out_json" \
      --header="Authorization: Bearer $api_key" \
      --header="Accept: application/json" \
      "$api_base/models" \
      2>"$err_file"
  else
    printf '%s\n' "缺少 curl/wget，无法获取模型" > "$err_file"
    return 1
  fi
}

choose_setup_mode() {
  printf '%s\n' "请选择 Codex 初始化方式：" >&2
  printf '%s\n' "1. 官方登录入口：进入 Codex 官方登录/API Key 流程，不写第三方 provider 配置" >&2
  printf '%s\n' "2. 第三方 Responses API：输入 Base URL 和 API Key，自动拉取模型并生成配置" >&2
  choice="$(tty_read "请输入选项编号" "2")"
  choice_lc="$(printf '%s' "$choice" | lower)"
  case "$choice_lc" in
    1|official|官方) printf '%s\n' "official" ;;
    *) printf '%s\n' "third_party" ;;
  esac
}

select_enabled_models_text() {
  list_file="$1"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1

  selected="$STATE_DIR/selected-model-indexes.txt"
  : > "$selected"
  seq 1 "$count" > "$selected"

  while :; do
    printf '\n%s\n' "选择常用模型（默认已全选，用于默认模型候选和本地记录）：" >&2
    i=1
    while [ "$i" -le "$count" ]; do
      model_name="$(sed -n "${i}p" "$list_file")"
      if grep -x "$i" "$selected" >/dev/null 2>&1; then
        mark="x"
      else
        mark=" "
      fi
      printf '  [%s] %2s. %s\n' "$mark" "$i" "$model_name" >&2
      i=$((i + 1))
    done
    printf '%s\n' "操作：输入编号切换选择，多个编号可用空格/逗号分隔；a=全选，n=清空。" >&2
    printf '%s\n' "选好了直接按回车即可；也可以输入 d/done 完成。" >&2
    picks="$(tty_read "多选操作（回车=完成）" "")"
    picks_lc="$(printf '%s' "$picks" | lower | tr ',' ' ')"
    case "$picks_lc" in
      ""|d|done|ok|y|yes|完成) break ;;
      a|all|全选)
        seq 1 "$count" > "$selected"
        printf '%s\n' "已全选。选好了直接按回车。" >&2
        continue
        ;;
      n|none|clear|清空)
        : > "$selected"
        printf '%s\n' "已清空选择。请至少选择一个常用模型，或继续按回车使用全部模型兜底。" >&2
        continue
        ;;
    esac

    changed=""
    printf '%s\n' "$picks_lc" | tr ' ' '\n' | while IFS= read -r n; do
      n="$(printf '%s' "$n" | sed 's/[^0-9]//g')"
      [ -n "$n" ] || continue
      [ "$n" -ge 1 ] 2>/dev/null || continue
      [ "$n" -le "$count" ] 2>/dev/null || continue
      if grep -x "$n" "$selected" >/dev/null 2>&1; then
        grep -vx "$n" "$selected" > "$selected.tmp" || true
        mv "$selected.tmp" "$selected"
      else
        printf '%s\n' "$n" >> "$selected"
        sort -n -u "$selected" -o "$selected"
      fi
    done
    printf '%s\n' "已更新选择。选好了直接按回车完成；还要调整就继续输入编号。" >&2
  done

  if [ ! -s "$selected" ]; then
    warn "未选择任何常用模型，默认使用全部模型作为候选。"
    cat "$list_file"
    return
  fi

  while IFS= read -r n; do
    sed -n "${n}p" "$list_file"
  done < "$selected"
}

choose_model() {
  list_file="$1"
  count="$(wc -l < "$list_file" | tr -d ' ')"
  [ "$count" -gt 0 ] || return 1
  printf '\n%s\n' "请选择默认启动模型：" >&2
  printf '%s\n' "这个模型会写入 config.toml 的 model 字段；Codex 后续会通过 provider auth 自行刷新 /models。" >&2
  nl -w2 -s'. ' "$list_file" >&2
  choice="$(tty_read "请输入默认启动模型编号" "1")"
  case "$choice" in
    *[!0-9]*|"") choice=1 ;;
  esac
  if [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "$count" ] 2>/dev/null; then
    choice=1
  fi
  chosen="$(sed -n "${choice}p" "$list_file")"
  printf '已选择默认启动模型：%s\n' "$chosen" >&2
  printf '%s\n' "$chosen"
}

read_auth_api_key() {
  auth_file="$1"
  [ -r "$auth_file" ] || return 1
  if have jq; then
    jq -r '.OPENAI_API_KEY // empty' "$auth_file" 2>/dev/null | sed -n '1p'
  else
    sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$auth_file" | sed -n '1p'
  fi
}

write_provider_auth_helper() {
  codex_home="$1"
  helper_dir="$codex_home/bin"
  helper="$helper_dir/provider-api-key"
  mkdir -p "$helper_dir"
  chmod 700 "$helper_dir"
  cat > "$helper" <<'EOF'
#!/usr/bin/env sh
set -eu

helper_path="$0"
case "$helper_path" in
  */*) helper_dir="${helper_path%/*}" ;;
  *) helper_dir="." ;;
esac

helper_home="$(CDPATH= cd -- "$helper_dir/.." 2>/dev/null && pwd || printf '%s' "${CODEX_HOME:-${HOME:-/root}/.codex}")"
auth_file="$helper_home/auth.json"
[ -r "$auth_file" ] || auth_file="${CODEX_HOME:-$helper_home}/auth.json"

token=""
if [ -r "$auth_file" ]; then
  if command -v jq >/dev/null 2>&1; then
    token="$(jq -r '.OPENAI_API_KEY // empty' "$auth_file" 2>/dev/null || true)"
  else
    token="$(sed -n 's/.*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$auth_file" 2>/dev/null | sed -n '1p')"
  fi
fi

[ -n "$token" ] || exit 1
printf '%s\n' "$token"
EOF
  chmod 700 "$helper"
}

model_display_name() {
  case "$1" in
    gpt-5.4-mini) printf '%s' "GPT-5.4-Mini" ;;
    gpt-5.5) printf '%s' "GPT-5.5" ;;
    codex-auto-review) printf '%s' "Codex Auto Review" ;;
    *) printf '%s' "$1" ;;
  esac
}

model_description() {
  case "$1" in
    gpt-5.4) printf '%s' "Strong model for everyday coding." ;;
    gpt-5.4-mini) printf '%s' "Small, fast, and cost-efficient model for simpler coding tasks." ;;
    gpt-5.5) printf '%s' "Frontier model for complex coding, research, and real-world work." ;;
    codex-auto-review) printf '%s' "Automatic approval review model for Codex." ;;
    gpt-5.3-codex-spark) printf '%s' "Provider API model exposed as gpt-5.3-codex-spark." ;;
    *) printf '%s' "Third-party provider model exposed by the current API." ;;
  esac
}

model_supports_reasoning() {
  case "$1" in
    gpt-image-*|*image*) return 1 ;;
    *) return 0 ;;
  esac
}

model_reasoning_levels_json() {
  if model_supports_reasoning "$1"; then
    printf '%s' '[{"effort":"low","description":"Fast responses with lighter reasoning"},{"effort":"medium","description":"Balances speed and reasoning depth for everyday tasks"},{"effort":"high","description":"Greater reasoning depth for complex problems"},{"effort":"xhigh","description":"Extra high reasoning depth for complex problems"}]'
  else
    printf '%s' '[]'
  fi
}

model_default_reasoning_json() {
  if model_supports_reasoning "$1"; then
    printf '%s' '"medium"'
  else
    printf '%s' 'null'
  fi
}

model_default_verbosity() {
  case "$1" in
    gpt-5.4-mini|gpt-image-2|deepseek-v4-flash:free) printf '%s' "medium" ;;
    *) printf '%s' "low" ;;
  esac
}

model_web_search_tool_type() {
  case "$1" in
    gpt-5.3-codex-spark) printf '%s' "text" ;;
    *) printf '%s' "text_and_image" ;;
  esac
}

model_priority() {
  case "$1" in
    gpt-image-2) printf '%s' "2" ;;
    gpt-5.5|codex-auto-review) printf '%s' "1" ;;
    *) printf '%s' "0" ;;
  esac
}

model_max_context_window() {
  case "$1" in
    gpt-5.4|codex-auto-review) printf '%s' "1000000" ;;
    *) printf '%s' "272000" ;;
  esac
}

model_availability_nux_level() {
  case "$1" in
    gpt-5.5) printf '%s' "4" ;;
    *) printf '%s' "3" ;;
  esac
}

append_model_availability_nux() {
  models_file="$1"
  default_model="$2"
  tmp_models="${STATE_DIR:-${TMPDIR:-/tmp}}/codex-model-availability.$$"
  fallback_file=""
  source_file="$models_file"

  if [ ! -s "$source_file" ] && [ -n "$default_model" ]; then
    fallback_file="$tmp_models.default"
    printf '%s\n' "$default_model" > "$fallback_file"
    source_file="$fallback_file"
  fi

  awk 'NF && !seen[$0]++ { print }' "$source_file" > "$tmp_models"
  if [ -s "$tmp_models" ]; then
    printf '\n[tui.model_availability_nux]\n'
    while IFS= read -r model; do
      [ -n "$model" ] || continue
      printf '"%s" = %s\n' "$(toml_escape "$model")" "$(model_availability_nux_level "$model")"
    done < "$tmp_models"
  fi

  rm -f "$tmp_models" "$fallback_file"
}

write_model_catalog() {
  models_file="$1"
  default_model="$2"
  out_json="$3"
  tmp_json="$out_json.tmp"
  dedup_file="$out_json.models.tmp"
  fallback_file=""
  source_file="$models_file"

  if [ ! -s "$source_file" ] && [ -n "$default_model" ]; then
    fallback_file="$out_json.default-model.tmp"
    printf '%s\n' "$default_model" > "$fallback_file"
    source_file="$fallback_file"
  fi

  awk 'NF && !seen[$0]++ { print }' "$source_file" > "$dedup_file"
  [ -s "$dedup_file" ] || die "无法生成模型目录：没有可写入 model_catalog_json 的模型名"

  {
    printf '{\n'
    printf '  "models": [\n'
    count=0
    while IFS= read -r model; do
      [ -n "$model" ] || continue
      model_esc="$(json_escape "$model")"
      display_name_esc="$(json_escape "$(model_display_name "$model")")"
      description_esc="$(json_escape "$(model_description "$model")")"
      default_reasoning_json="$(model_default_reasoning_json "$model")"
      reasoning_levels_json="$(model_reasoning_levels_json "$model")"
      default_verbosity="$(model_default_verbosity "$model")"
      web_search_tool_type="$(model_web_search_tool_type "$model")"
      priority="$(model_priority "$model")"
      max_context_window="$(model_max_context_window "$model")"
      [ "$count" -eq 0 ] || printf ',\n'
      cat <<EOF
    {
      "prefer_websockets": true,
      "support_verbosity": true,
      "default_verbosity": "$default_verbosity",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "$web_search_tool_type",
      "input_modalities": ["text", "image"],
      "supports_image_detail_original": true,
      "truncation_policy": {"mode": "tokens", "limit": 10000},
      "supports_parallel_tool_calls": true,
      "context_window": 272000,
      "max_context_window": $max_context_window,
      "auto_compact_token_limit": 120000,
      "reasoning_summary_format": "experimental",
      "default_reasoning_summary": "none",
      "slug": "$model_esc",
      "display_name": "$display_name_esc",
      "description": "$description_esc",
      "default_reasoning_level": $default_reasoning_json,
      "supported_reasoning_levels": $reasoning_levels_json,
      "shell_type": "shell_command",
      "visibility": "list",
      "minimal_client_version": "0.98.0",
      "supported_in_api": true,
      "availability_nux": null,
      "upgrade": null,
      "priority": $priority,
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
    done < "$dedup_file"
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } > "$tmp_json"

  mv "$tmp_json" "$out_json"
  chmod 600 "$out_json"
  rm -f "$dedup_file" "$fallback_file"
}

write_codex_config() {
  api_base="$1"
  api_key="$2"
  default_model="$3"
  models_file="$4"
  out_home="${5:-$CODEX_HOME}"

  mkdir -p "$out_home"
  chmod 700 "$out_home"

  auth_file="$out_home/auth.json"
  {
    printf '{\n'
    printf '  "OPENAI_API_KEY": "%s"\n' "$(json_escape "$api_key")"
    printf '}\n'
  } > "$auth_file"
  chmod 600 "$auth_file"
  write_provider_auth_helper "$out_home"
  write_model_catalog "$models_file" "$default_model" "$(model_catalog_path "$out_home")"
  rm -f "$(legacy_model_catalog_path "$out_home")"

  config_file="$out_home/config.toml"
  provider_id_esc="$(toml_escape "$PROVIDER_ID")"
  default_model_esc="$(toml_escape "$default_model")"
  api_base_esc="$(toml_escape "$api_base")"
  home_esc="$(toml_escape "$HOME")"
  out_home_esc="$(toml_escape "$out_home")"
  auth_command_esc="$(toml_escape "$out_home/bin/provider-api-key")"
  model_catalog_esc="$(toml_escape "$(model_catalog_path "$out_home")")"
  {
    printf 'model_catalog_json = "%s"\n' "$model_catalog_esc"
    printf 'model_provider = "%s"\n' "$provider_id_esc"
    printf 'model = "%s"\n' "$default_model_esc"
    printf 'model_reasoning_effort = "medium"\n'
    printf 'model_auto_compact_token_limit = 120000\n'
    printf 'disable_response_storage = true\n'
    printf '\n[features]\n'
    printf 'auto_compaction = true\n'
    printf 'hooks = false\n'
    printf '\n[model_providers.%s]\n' "$PROVIDER_ID"
    printf 'name = "%s"\n' "$provider_id_esc"
    printf 'base_url = "%s"\n' "$api_base_esc"
    printf 'wire_api = "responses"\n'
    printf 'requires_openai_auth = false\n'
    printf '\n[model_providers.%s.auth]\n' "$PROVIDER_ID"
    printf 'command = "%s"\n' "$auth_command_esc"
    printf 'args = []\n'
    printf 'timeout_ms = 5000\n'
    printf 'refresh_interval_ms = 300000\n'
    printf 'cwd = "%s"\n' "$out_home_esc"
    printf '\n[projects."%s"]\n' "$home_esc"
    printf 'trust_level = "trusted"\n'
    printf '\n[tui]\n'
    printf 'status_line = ["model-with-reasoning", "current-dir", "context-remaining"]\n'
    printf 'status_line_use_colors = true\n'
    append_model_availability_nux "$models_file" "$default_model"
    printf '\n[notice]\n'
    printf 'hide_full_access_warning = true\n'
    printf '\n[notice.model_migrations]\n'
    printf '"gpt-5.4mini" = "gpt-5.4-mini"\n'
    printf '"gpt-5.3-codex" = "gpt-5.4"\n'
    printf '"gpt-5.2" = "gpt-5.4"\n'
  } > "$config_file"
  chmod 600 "$config_file"
}

write_standard_agents() {
  out="$1"
  cat > "$out" <<'EOF'
# AGENTS.md

## 身份
- 你是 Codex，运行在 Android/Codex for TUI Alpine 环境中的编程助手。
- 优先帮助用户把事情做完，回答简洁、可执行。

## 工作方式
- 修改文件前先理解上下文。
- 不要擅自删除或覆盖用户文件。
- 遇到不确定或高风险操作先确认。
- 优先使用 rg、sed、git 等本地工具验证。

## 输出
- 先给结论，再给必要步骤。
- 如果命令失败，说明原因和下一步。
EOF
}

setup_agents_md_if_needed() {
  mkdir -p "$CODEX_HOME"
  agents_file="$CODEX_HOME/AGENTS.md"
  home_agents="$HOME/AGENTS.md"
  rm -f "$CODEX_HOME/AGENTS.standard.md"
  if [ -s "$agents_file" ]; then
    cp "$agents_file" "$home_agents" 2>/dev/null || true
    return
  fi

  section_title "本地配置 1/2：启动提示词"
  printf '%s\n' "请选择启动提示词：" >&2
  printf '\n%s\n' "  1. 默认 AGENTS.md" >&2
  printf '%s\n' "     生成标准版系统提示词，每次启动自动带上。" >&2
  printf '\n%s\n' "  2. 自定义 AGENTS.md" >&2
  printf '%s\n' "     现在粘贴你的内容，适合已有固定提示词。" >&2
  printf '\n%s\n' "  q. 退出，稍后继续" >&2
  printf '\n' >&2
  choice_lc="$(menu_read "请输入选项编号" "1" "1 2 q" "可选：1 / 2 / q")"
  case "$choice_lc" in
    2)
      info "请输入自定义 AGENTS.md 内容。单独输入一行 EOF 结束。"
      : > "$agents_file"
      while :; do
        if tty_available; then IFS= read -r line < /dev/tty || break; else IFS= read -r line || break; fi
        [ "$line" = "EOF" ] && break
        printf '%s\n' "$line" >> "$agents_file"
      done
      [ -s "$agents_file" ] || write_standard_agents "$agents_file"
      ;;
    q) exit_for_later ;;
    *) write_standard_agents "$agents_file" ;;
  esac
  cp "$agents_file" "$home_agents" 2>/dev/null || true
  chmod 600 "$agents_file" "$home_agents" 2>/dev/null || true
}

migrate_third_party_profile_if_needed() {
  profile_dir="$1"
  [ -s "$profile_dir/setup-mode" ] || return 0
  [ "$(sed -n '1p' "$profile_dir/setup-mode")" = "third_party" ] || return 0
  [ -s "$profile_dir/config.toml" ] || return 0

  needs_migration=0
  grep -F 'model_catalog_json' "$profile_dir/config.toml" >/dev/null 2>&1 || needs_migration=1
  grep -F "[model_providers.$PROVIDER_ID.auth]" "$profile_dir/config.toml" >/dev/null 2>&1 || needs_migration=1
  [ -s "$(model_catalog_path "$profile_dir")" ] || needs_migration=1
  [ "$needs_migration" = "1" ] || return 0

  api_base="$(sed -n '1p' "$profile_dir/api-base" 2>/dev/null || true)"
  [ -n "$api_base" ] || api_base="$(sed -n 's/^[[:space:]]*base_url[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$profile_dir/config.toml" | sed -n '1p')"
  default_model="$(sed -n '1p' "$profile_dir/default-model" 2>/dev/null || true)"
  [ -n "$default_model" ] || default_model="$(sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$profile_dir/config.toml" | sed -n '1p')"
  enabled_file="$profile_dir/enabled-models.txt"
  models_file="$profile_dir/models.txt"
  if [ ! -s "$models_file" ] && [ -s "$enabled_file" ]; then
    cp "$enabled_file" "$models_file"
  fi
  if [ ! -s "$enabled_file" ] && [ -n "$default_model" ]; then
    printf '%s\n' "$default_model" > "$enabled_file"
  fi
  if [ ! -s "$models_file" ] && [ -n "$default_model" ]; then
    printf '%s\n' "$default_model" > "$models_file"
  fi
  api_key="$(read_auth_api_key "$profile_dir/auth.json" 2>/dev/null || true)"

  [ -n "$api_base" ] || die "旧配置缺少 API Base URL，无法自动迁移：$profile_dir"
  [ -n "$default_model" ] || die "旧配置缺少默认模型，无法自动迁移：$profile_dir"
  [ -n "$api_key" ] || die "旧配置 auth.json 缺少 OPENAI_API_KEY，无法自动迁移：$profile_dir"

  write_codex_config "$api_base" "$api_key" "$default_model" "$models_file" "$profile_dir"
  warn "已迁移旧第三方配置：补齐 provider command auth，并重新生成 model_catalog_json。"
}

apply_profile() {
  profile_dir="$1"
  [ -d "$profile_dir" ] || die "配置不存在：$profile_dir"
  if [ -s "$profile_dir/setup-mode" ] && [ "$(profile_mode "$profile_dir")" = "official" ]; then
    if [ ! -s "$LAST_PROFILE_FILE" ] && { [ -s "$CODEX_HOME/config.toml" ] || [ -s "$CODEX_HOME/auth.json" ]; }; then
      ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo legacy)"
      backup_dir="$CONFIGS_DIR/imported-before-official-$ts"
      mkdir -p "$backup_dir"
      printf '%s\n' "切换官方前自动备份" > "$backup_dir/name"
      printf '%s\n' "third_party" > "$backup_dir/setup-mode"
      [ ! -s "$CODEX_HOME/config.toml" ] || cp "$CODEX_HOME/config.toml" "$backup_dir/config.toml"
      [ ! -s "$CODEX_HOME/auth.json" ] || cp "$CODEX_HOME/auth.json" "$backup_dir/auth.json"
      copy_model_catalog_file "$CODEX_HOME" "$backup_dir"
      chmod 700 "$backup_dir" 2>/dev/null || true
      chmod 600 "$backup_dir/config.toml" "$backup_dir/auth.json" "$(model_catalog_path "$backup_dir")" 2>/dev/null || true
      warn "已先把当前 ~/.codex 配置备份为：$backup_dir"
    fi
    rm -f "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json"
    remove_model_catalog_files "$CODEX_HOME"
    [ ! -s "$profile_dir/config.toml" ] || cp "$profile_dir/config.toml" "$CODEX_HOME/config.toml"
    [ ! -s "$profile_dir/auth.json" ] || cp "$profile_dir/auth.json" "$CODEX_HOME/auth.json"
    chmod 600 "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json" 2>/dev/null || true
  else
    migrate_third_party_profile_if_needed "$profile_dir"
    ensure_third_party_profile_usable "$profile_dir" || die "第三方配置缺少必要文件，无法启用：$profile_dir。请到“管理已有配置”里删除后重建。"
    [ -s "$profile_dir/config.toml" ] || die "配置缺少 config.toml：$profile_dir"
    [ -s "$profile_dir/auth.json" ] || die "配置缺少 auth.json：$profile_dir"
    cp "$profile_dir/config.toml" "$CODEX_HOME/config.toml"
    cp "$profile_dir/auth.json" "$CODEX_HOME/auth.json"
    copy_model_catalog_file "$profile_dir" "$CODEX_HOME"
    if [ -x "$profile_dir/bin/provider-api-key" ]; then
      mkdir -p "$CODEX_HOME/bin"
      cp "$profile_dir/bin/provider-api-key" "$CODEX_HOME/bin/provider-api-key"
      chmod 700 "$CODEX_HOME/bin" "$CODEX_HOME/bin/provider-api-key" 2>/dev/null || true
    fi
    chmod 600 "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json" "$(model_catalog_path "$CODEX_HOME")" 2>/dev/null || true
  fi
  basename "$profile_dir" > "$LAST_PROFILE_FILE"
  profile_label "$profile_dir" > "$STATE_DIR/active-profile-label"
}

clear_active_profile_state() {
  rm -f \
    "$CODEX_HOME/config.toml" \
    "$CODEX_HOME/auth.json" \
    "$CODEX_HOME/bin/provider-api-key" \
    "$STATE_DIR/active-profile-label"
  remove_model_catalog_files "$CODEX_HOME"
  rmdir "$CODEX_HOME/bin" 2>/dev/null || true
}

sync_current_profile() {
  last_slug="$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)"
  [ -n "$last_slug" ] || return 0
  profile_dir="$CONFIGS_DIR/$last_slug"
  [ -d "$profile_dir" ] || return 0
  [ -s "$profile_dir/setup-mode" ] || return 0

  mode="$(sed -n '1p' "$profile_dir/setup-mode")"
  mkdir -p "$profile_dir"
  chmod 700 "$profile_dir" 2>/dev/null || true
  case "$mode" in
    official)
      [ ! -s "$CODEX_HOME/auth.json" ] || cp "$CODEX_HOME/auth.json" "$profile_dir/auth.json"
      [ ! -s "$CODEX_HOME/config.toml" ] || cp "$CODEX_HOME/config.toml" "$profile_dir/config.toml"
      ;;
    third_party)
      [ ! -s "$CODEX_HOME/config.toml" ] || cp "$CODEX_HOME/config.toml" "$profile_dir/config.toml"
      [ ! -s "$CODEX_HOME/auth.json" ] || cp "$CODEX_HOME/auth.json" "$profile_dir/auth.json"
      copy_model_catalog_file "$CODEX_HOME" "$profile_dir"
      if [ -x "$CODEX_HOME/bin/provider-api-key" ]; then
        mkdir -p "$profile_dir/bin"
        cp "$CODEX_HOME/bin/provider-api-key" "$profile_dir/bin/provider-api-key"
        chmod 700 "$profile_dir/bin" "$profile_dir/bin/provider-api-key" 2>/dev/null || true
      fi
      ;;
  esac
  chmod 600 "$profile_dir/config.toml" "$profile_dir/auth.json" "$(model_catalog_path "$profile_dir")" 2>/dev/null || true
}

fetch_models_or_prompt() {
  api_base="$1"
  api_key="$2"
  models_file="$3"
  models_json="$4"
  models_err="$5"

  while :; do
    printf '%s\n' "正在请求模型列表：$api_base/models" >&2
    printf '%s\n' "网络较慢时这一步可能需要几十秒，请稍候..." >&2
    printf '\n' >&2
    : > "$models_file"
    : > "$models_err"
    if fetch_models "$api_base" "$api_key" "$models_json" "$models_err"; then
      parse_models "$models_json" > "$models_file"
      if [ -s "$models_file" ]; then
        return 0
      fi
      warn "接口已返回，但没有解析到任何模型。"
      [ -s "$models_json" ] && sed -n '1,12p' "$models_json" >&2 || true
    else
      warn "获取模型列表失败：$api_base/models"
      [ -s "$models_err" ] && sed -n '1,20p' "$models_err" >&2 || true
    fi

    warn "不会让你手填模型名，也不会清掉本地安装成果。"
    printf '%s\n' "请选择下一步：" >&2
    printf '\n%s\n' "  1. 重试获取模型列表" >&2
    printf '\n%s\n' "  2. 重新填写 API Base URL 和 API Key" >&2
    printf '\n%s\n' "  q. 退出，稍后再运行 codex 继续" >&2
    printf '\n' >&2
    choice="$(menu_read "请输入选项编号" "2" "1 2 q" "可选：1 / 2 / q")"
    case "$choice" in
      1) ;;
      2) return 2 ;;
      q) return 1 ;;
    esac
  done
}

preserve_enabled_models() {
  old_enabled="$1"
  new_models="$2"
  out_enabled="$3"

  : > "$out_enabled"
  if [ -s "$old_enabled" ]; then
    awk '
      NR == FNR { available[$0] = 1; next }
      NF && available[$0] && !seen[$0]++ { print }
    ' "$new_models" "$old_enabled" > "$out_enabled"
  fi
  [ -s "$out_enabled" ] || cp "$new_models" "$out_enabled"
}

pick_refreshed_default_model() {
  current_default="$1"
  enabled_file="$2"
  models_file="$3"

  if list_has_line "$current_default" "$models_file"; then
    printf '%s\n' "$current_default"
    return 0
  fi
  if [ -s "$enabled_file" ]; then
    sed -n '1p' "$enabled_file"
    return 0
  fi
  sed -n '1p' "$models_file"
}

refresh_current_profile() {
  mkdir -p "$CODEX_HOME" "$STATE_DIR" "$CONFIGS_DIR"
  chmod 700 "$CODEX_HOME" "$STATE_DIR" "$CONFIGS_DIR" 2>/dev/null || true
  sync_current_profile

  profile_dir="$(current_profile_dir 2>/dev/null || true)"
  [ -n "$profile_dir" ] || die "当前没有可刷新的已激活配置。请先运行 codex-local-resume 选择或新建配置。"

  mode="$(profile_mode "$profile_dir")"
  case "$mode" in
    official)
      info "当前配置是官方登录入口；不需要刷新第三方模型目录。"
      return 0
      ;;
    third_party) ;;
    *)
      die "无法识别当前配置类型：$profile_dir"
      ;;
  esac

  profile_name="$(profile_label "$profile_dir")"
  api_base="$(profile_api_base "$profile_dir")"
  api_key="$(read_auth_api_key "$profile_dir/auth.json" 2>/dev/null || true)"
  current_default="$(profile_default_model "$profile_dir")"
  [ -n "$api_base" ] || die "当前配置缺少 API Base URL，无法刷新：$profile_dir"
  [ -n "$api_key" ] || die "当前配置缺少 API Key，无法刷新：$profile_dir"

  work_dir="$STATE_DIR/refresh-profile"
  rm -rf "$work_dir"
  mkdir -p "$work_dir"
  models_file="$work_dir/models.txt"
  models_json="$work_dir/models.json"
  models_err="$work_dir/models.err"
  enabled_file="$work_dir/enabled-models.txt"

  while :; do
    if fetch_models_or_prompt "$api_base" "$api_key" "$models_file" "$models_json" "$models_err"; then
      break
    else
      rc="$?"
    fi
    [ "$rc" = "2" ] || exit_for_later

    section_title "本地配置：刷新当前配置"
    printf '%s\n' "正在刷新：$profile_name" >&2
    printf '%s\n' "接口请求失败，请确认 API Base URL / API Key。" >&2
    printf '%s\n' "输入 q 退出，稍后继续。" >&2
    printf '\n' >&2

    raw_base="$(tty_read "API Base URL" "$api_base")"
    case "$(printf '%s' "$raw_base" | lower)" in
      q|quit|exit|退出) exit_for_later ;;
    esac
    if ! valid_api_base_input "$raw_base"; then
      warn "API Base URL 格式不对：$raw_base"
      warn "必须以 http:// 或 https:// 开头，例如 https://api.example.com/v1"
      printf '\n' >&2
      continue
    fi

    printf '%s\n' "如需沿用当前 API Key，直接回车即可。" >&2
    new_api_key="$(tty_read_api_key "新的 API Key（留空则保持当前）")"
    case "$(printf '%s' "$new_api_key" | lower)" in
      q|quit|exit|退出) exit_for_later ;;
    esac
    [ -n "$new_api_key" ] || new_api_key="$api_key"

    api_base="$(normalize_api_base "$raw_base")"
    api_key="$new_api_key"
    printf '\n%s\n' "规范化后的 API Base URL: $api_base" >&2
    printf '%s\n' "下一步会重新请求：$api_base/models" >&2
    printf '\n' >&2
  done

  preserve_enabled_models "$profile_dir/enabled-models.txt" "$models_file" "$enabled_file"
  default_model="$(pick_refreshed_default_model "$current_default" "$enabled_file" "$models_file")"
  [ -n "$default_model" ] || die "刷新后没有可用模型，无法更新配置：$profile_dir"
  if ! list_has_line "$default_model" "$enabled_file"; then
    printf '%s\n' "$default_model" >> "$enabled_file"
  fi
  if [ "$default_model" != "$current_default" ]; then
    warn "默认模型已从 $current_default 调整为 $default_model，因为原模型不在最新 /models 列表里。"
  fi

  printf '%s\n' "$profile_name" > "$profile_dir/name"
  printf '%s\n' "third_party" > "$profile_dir/setup-mode"
  printf '%s\n' "$api_base" > "$profile_dir/api-base"
  printf '%s\n' "$default_model" > "$profile_dir/default-model"
  cp "$models_file" "$profile_dir/models.txt"
  cp "$enabled_file" "$profile_dir/enabled-models.txt"
  write_codex_config "$api_base" "$api_key" "$default_model" "$models_file" "$profile_dir"
  apply_profile "$profile_dir"
  rm -rf "$work_dir"
  info "已刷新当前配置：$profile_name"
}

create_official_profile() {
  profile_dir="$CONFIGS_DIR/official"
  mkdir -p "$profile_dir"
  printf '%s\n' "官方登录入口" > "$profile_dir/name"
  printf '%s\n' "official" > "$profile_dir/setup-mode"
  apply_profile "$profile_dir"
}

edit_third_party_profile() {
  profile_dir="$1"
  [ -d "$profile_dir" ] || die "配置不存在：$profile_dir"
  [ "$(profile_mode "$profile_dir")" = "third_party" ] || die "只有第三方 Responses API 配置支持编辑：$profile_dir"

  work_dir="$STATE_DIR/edit-profile"
  rm -rf "$work_dir"
  mkdir -p "$work_dir"

  current_name="$(profile_label "$profile_dir")"
  current_base="$(profile_api_base "$profile_dir")"
  current_key="$(read_auth_api_key "$profile_dir/auth.json" 2>/dev/null || true)"
  [ -n "$current_base" ] || die "配置缺少 API Base URL，无法编辑：$profile_dir"
  [ -n "$current_key" ] || die "配置缺少 API Key，无法编辑：$profile_dir"

  while :; do
    section_title "本地配置 2/2：编辑第三方配置"
    printf '%s\n' "正在编辑：$current_name" >&2
    printf '%s\n' "输入 b 返回上一层；输入 q 退出，稍后继续。" >&2
    printf '\n' >&2

    profile_name="$(tty_read "配置名称" "$current_name")"
    case "$(printf '%s' "$profile_name" | lower)" in
      b|back|返回) return 2 ;;
      q|quit|exit|退出) exit_for_later ;;
    esac

    raw_base="$(tty_read "API Base URL" "$current_base")"
    case "$(printf '%s' "$raw_base" | lower)" in
      b|back|返回) return 2 ;;
      q|quit|exit|退出) exit_for_later ;;
    esac
    if ! valid_api_base_input "$raw_base"; then
      warn "API Base URL 格式不对：$raw_base"
      warn "必须以 http:// 或 https:// 开头，例如 https://api.example.com/v1"
      printf '\n' >&2
      continue
    fi

    printf '%s\n' "如需沿用当前 API Key，直接回车即可。" >&2
    api_key="$(tty_read_api_key "新的 API Key（留空则保持当前）")"
    case "$(printf '%s' "$api_key" | lower)" in
      b|back|返回) return 2 ;;
      q|quit|exit|退出) exit_for_later ;;
    esac
    [ -n "$api_key" ] || api_key="$current_key"

    api_base="$(normalize_api_base "$raw_base")"
    printf '\n%s\n' "规范化后的 API Base URL: $api_base" >&2
    printf '%s\n' "下一步会请求：$api_base/models" >&2
    printf '\n' >&2

    models_file="$work_dir/models.txt"
    models_json="$work_dir/models.json"
    models_err="$work_dir/models.err"
    if fetch_models_or_prompt "$api_base" "$api_key" "$models_file" "$models_json" "$models_err"; then
      break
    else
      rc="$?"
    fi
    [ "$rc" = "2" ] || exit_for_later
  done

  enabled_file="$work_dir/enabled-models.txt"
  default_file="$work_dir/default-model.txt"
  select_enabled_models_text "$models_file" > "$enabled_file"
  choose_model "$enabled_file" > "$default_file"
  default_model="$(sed -n '1p' "$default_file")"

  printf '%s\n' "$profile_name" > "$profile_dir/name"
  printf '%s\n' "third_party" > "$profile_dir/setup-mode"
  printf '%s\n' "$api_base" > "$profile_dir/api-base"
  printf '%s\n' "$default_model" > "$profile_dir/default-model"
  cp "$models_file" "$profile_dir/models.txt"
  cp "$enabled_file" "$profile_dir/enabled-models.txt"
  write_codex_config "$api_base" "$api_key" "$default_model" "$models_file" "$profile_dir"
  apply_profile "$profile_dir"
  rm -rf "$work_dir"
  info "已更新第三方配置：$profile_name"
}

delete_profile() {
  profile_dir="$1"
  [ -d "$profile_dir" ] || die "配置不存在：$profile_dir"
  label="$(profile_label "$profile_dir")"
  mode="$(profile_mode "$profile_dir")"

  section_title "本地配置 2/2：删除配置"
  printf '%s\n' "即将删除：" >&2
  printf '%s\n' "名称：$label" >&2
  printf '%s\n' "类型：$mode" >&2
  if [ "$(basename "$profile_dir")" = "$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)" ]; then
    printf '%s\n' "这也是当前激活的配置，删除后会一并清空 ~/.codex 当前副本。" >&2
  fi
  printf '\n' >&2
  choice="$(menu_read "确认删除？y=删除，n=取消，q=退出" "n" "y n q" "删除后该配置目录会被移除。")"
  case "$choice" in
    q) exit_for_later ;;
    n) return 1 ;;
  esac

  last_slug="$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)"
  if [ "$(basename "$profile_dir")" = "$last_slug" ]; then
    clear_active_profile_state
    rm -f "$LAST_PROFILE_FILE"
  fi
  rm -rf "$profile_dir"
  info "已删除配置：$label"
}

manage_existing_profiles() {
  profiles_file="$1"
  count="$2"
  [ "$count" -gt 0 ] || return 0

  while :; do
    section_title "本地配置 2/2：管理已有配置"
    printf '%s\n' "请选择要管理的配置：" >&2
    i=1
    while [ "$i" -le "$count" ]; do
      d="$(sed -n "${i}p" "$profiles_file")"
      suffix=""
      if ! profile_is_usable "$d"; then
        suffix="（配置缺失，启动时已跳过）"
      fi
      printf '\n%2s. %s [%s] %s\n' "$i" "$(profile_label "$d")" "$(profile_mode "$d")" "$suffix" >&2
      i=$((i + 1))
    done
    printf '\n%s\n' " b. 返回上一层" >&2
    printf '%s\n' " q. 退出，稍后继续" >&2
    printf '\n' >&2

    allowed="b q"
    i=1
    while [ "$i" -le "$count" ]; do allowed="$allowed $i"; i=$((i + 1)); done
    choice="$(menu_read "请输入选项编号" "b" "$allowed" "请选择列表里的编号，或输入 b / q。")"
    case "$choice" in
      b) return 0 ;;
      q) exit_for_later ;;
    esac

    profile_dir="$(sed -n "${choice}p" "$profiles_file")"
    mode="$(profile_mode "$profile_dir")"
    usable=1
    if profile_is_usable "$profile_dir"; then
      usable=0
    fi
    while :; do
      section_title "本地配置 2/2：管理 $(profile_label "$profile_dir")"
      if [ "$usable" = "0" ]; then
        printf '%s\n' "类型：$mode" >&2
        printf '\n%s\n' "  1. 直接切换到这个配置" >&2
      else
        printf '%s\n' "类型：$mode（当前缺少必要文件）" >&2
      fi
      if [ "$mode" = "third_party" ] && [ "$usable" = "0" ]; then
        printf '\n%s\n' "  2. 编辑供应商配置（Base URL / API Key / 模型列表 / 默认模型）" >&2
        printf '\n%s\n' "  3. 删除这个配置" >&2
        printf '\n%s\n' "  b. 返回配置列表" >&2
        printf '%s\n' "  q. 退出，稍后继续" >&2
        printf '\n' >&2
        action="$(menu_read "请输入选项编号" "1" "1 2 3 b q" "可选：1 / 2 / 3 / b / q")"
        case "$action" in
          1) apply_profile "$profile_dir"; return 10 ;;
          2)
            if edit_third_party_profile "$profile_dir"; then
              return 0
            else
              rc="$?"
              [ "$rc" = "2" ] && break
              exit_for_later
            fi
            ;;
          3)
            delete_profile "$profile_dir" || true
            return 0
            ;;
          b) break ;;
          q) exit_for_later ;;
        esac
      elif [ "$usable" = "0" ]; then
        printf '\n%s\n' "  2. 删除这个配置" >&2
        printf '\n%s\n' "  b. 返回配置列表" >&2
        printf '%s\n' "  q. 退出，稍后继续" >&2
        printf '\n' >&2
        action="$(menu_read "请输入选项编号" "1" "1 2 b q" "可选：1 / 2 / b / q")"
        case "$action" in
          1) apply_profile "$profile_dir"; return 10 ;;
          2)
            delete_profile "$profile_dir" || true
            return 0
            ;;
          b) break ;;
          q) exit_for_later ;;
        esac
      else
        printf '%s\n' "这个配置缺少必要文件，暂时不能直接启用。" >&2
        printf '\n%s\n' "  1. 删除这个配置" >&2
        printf '\n%s\n' "  b. 返回配置列表" >&2
        printf '%s\n' "  q. 退出，稍后继续" >&2
        printf '\n' >&2
        action="$(menu_read "请输入选项编号" "1" "1 b q" "可选：1 / b / q")"
        case "$action" in
          1)
            delete_profile "$profile_dir" || true
            return 0
            ;;
          b) break ;;
          q) exit_for_later ;;
        esac
      fi
    done
  done
}

create_third_party_profile() {
  work_dir="$STATE_DIR/new-profile"
  rm -rf "$work_dir"
  mkdir -p "$work_dir"

  while :; do
    section_title "本地配置 2/2：第三方 Responses API"
    raw_base="${CODEX_ZH_API_BASE:-}"
    api_key="${CODEX_ZH_API_KEY:-}"
    if [ -z "$raw_base" ]; then
      printf '%s\n' "请输入 API Base URL。" >&2
      printf '%s\n' "示例：https://api.example.com 或 https://api.example.com/v1" >&2
      printf '%s\n' "输入 b 返回配置类型选择；输入 q 退出，稍后继续。" >&2
      printf '\n' >&2
      raw_base="$(tty_read "API Base URL" "")"
    fi
    case "$(printf '%s' "$raw_base" | lower)" in
      b|back|返回) return 2 ;;
      q|quit|exit|退出) exit_for_later ;;
    esac
    if ! valid_api_base_input "$raw_base"; then
      warn "API Base URL 格式不对：$raw_base"
      warn "必须以 http:// 或 https:// 开头，例如 https://api.example.com/v1"
      unset CODEX_ZH_API_BASE
      printf '\n' >&2
      continue
    fi
    [ -n "$api_key" ] || api_key="$(tty_read_api_key "请输入 API Key")"
    case "$(printf '%s' "$api_key" | lower)" in
      b|back|返回) return 2 ;;
      q|quit|exit|退出) exit_for_later ;;
    esac
    [ -n "$api_key" ] || die "API Key 不能为空"
    api_base="$(normalize_api_base "$raw_base")"
    printf '\n%s\n' "规范化后的 API Base URL: $api_base" >&2
    printf '%s\n' "下一步会请求：$api_base/models" >&2
    printf '%s\n' "如果网络或 Key 有问题，会返回重试/重填/退出菜单。" >&2
    printf '\n' >&2

    models_file="$work_dir/models.txt"
    models_json="$work_dir/models.json"
    models_err="$work_dir/models.err"
    if fetch_models_or_prompt "$api_base" "$api_key" "$models_file" "$models_json" "$models_err"; then
      break
    else
      rc="$?"
    fi
    [ "$rc" = "2" ] || exit_for_later
    unset CODEX_ZH_API_BASE CODEX_ZH_API_KEY
  done

  enabled_file="$work_dir/enabled-models.txt"
  default_file="$work_dir/default-model.txt"
  select_enabled_models_text "$models_file" > "$enabled_file"
  choose_model "$enabled_file" > "$default_file"
  default_model="$(sed -n '1p' "$default_file")"

  default_name="$(printf '%s' "$api_base" | sed 's#^https\?://##; s#/v1$##; s#[/:]#-#g')"
  profile_name="$(tty_read "请输入这个 API 配置的名称，方便以后切换" "$default_name")"
  slug="$(profile_slug "$profile_name")"
  profile_dir="$CONFIGS_DIR/$slug"
  if [ -e "$profile_dir" ]; then
    suffix=2
    while [ -e "$CONFIGS_DIR/$slug-$suffix" ]; do suffix=$((suffix + 1)); done
    profile_dir="$CONFIGS_DIR/$slug-$suffix"
  fi
  mkdir -p "$profile_dir"
  chmod 700 "$profile_dir" 2>/dev/null || true
  printf '%s\n' "$profile_name" > "$profile_dir/name"
  printf '%s\n' "third_party" > "$profile_dir/setup-mode"
  printf '%s\n' "$api_base" > "$profile_dir/api-base"
  printf '%s\n' "$default_model" > "$profile_dir/default-model"
  cp "$models_file" "$profile_dir/models.txt"
  cp "$enabled_file" "$profile_dir/enabled-models.txt"
  write_codex_config "$api_base" "$api_key" "$default_model" "$models_file" "$profile_dir"
  apply_profile "$profile_dir"
}

select_or_create_profile() {
  mkdir -p "$CONFIGS_DIR" "$STATE_DIR"
  chmod 700 "$CONFIGS_DIR" "$STATE_DIR" 2>/dev/null || true
  sync_current_profile

  while :; do
    all_profiles_file="$STATE_DIR/all-profiles.txt"
    profiles_file="$STATE_DIR/profiles.txt"
    broken_profiles_file="$STATE_DIR/broken-profiles.txt"
    : > "$all_profiles_file"
    : > "$profiles_file"
    : > "$broken_profiles_file"
    for d in "$CONFIGS_DIR"/*; do
      [ -d "$d" ] || continue
      [ -s "$d/setup-mode" ] || continue
      printf '%s\n' "$d" >> "$all_profiles_file"
      if profile_is_usable "$d"; then
        printf '%s\n' "$d" >> "$profiles_file"
      else
        printf '%s\n' "$d" >> "$broken_profiles_file"
      fi
    done

    last_slug="$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)"
    default_choice=""
    all_count="$(wc -l < "$all_profiles_file" | tr -d ' ')"
    count="$(wc -l < "$profiles_file" | tr -d ' ')"
    broken_count="$(wc -l < "$broken_profiles_file" | tr -d ' ')"
    if [ "$count" -gt 0 ]; then
      section_title "本地配置 2/2：选择 Codex 配置"
      if [ "$broken_count" -gt 0 ]; then
        warn "已跳过 $broken_count 个缺少必要文件的本地配置；可进入“管理已有配置”删除。"
        printf '\n' >&2
      fi
      printf '%s\n' "请选择本次启动使用的 Codex 配置：" >&2
      i=1
      while [ "$i" -le "$count" ]; do
        d="$(sed -n "${i}p" "$profiles_file")"
        label="$(profile_label "$d")"
        mode="$(profile_mode "$d")"
        mark=""
        if [ "$(basename "$d")" = "$last_slug" ]; then
          mark="（上次使用）"
          default_choice="$i"
        fi
        printf '\n%2s. %s [%s] %s\n' "$i" "$label" "$mode" "$mark" >&2
        i=$((i + 1))
      done
      new_choice=$((count + 1))
      manage_choice=$((count + 2))
      printf '\n%2s. 新建配置\n' "$new_choice" >&2
      printf '\n%2s. 管理已有配置\n' "$manage_choice" >&2
      printf '\n%s\n' " q. 退出，稍后继续" >&2
      printf '\n' >&2
      [ -n "$default_choice" ] || default_choice="$new_choice"
      allowed="q"
      i=1
      while [ "$i" -le "$manage_choice" ]; do allowed="$allowed $i"; i=$((i + 1)); done
      choice="$(menu_read "请输入选项编号" "$default_choice" "$allowed" "请选择列表里的编号，或输入 q 退出。")"
      [ "$choice" = "q" ] && exit_for_later
      if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ] 2>/dev/null; then
        apply_profile "$(sed -n "${choice}p" "$profiles_file")"
        return
      fi
      if [ "$choice" = "$manage_choice" ]; then
        if manage_existing_profiles "$all_profiles_file" "$all_count"; then
          continue
        else
          rc="$?"
          [ "$rc" = "10" ] && return
          exit_for_later
        fi
      fi
    fi

    section_title "本地配置 2/2：新建 Codex 配置"
    if [ "$broken_count" -gt 0 ]; then
      warn "检测到 $broken_count 个缺少必要文件的本地配置；已从启动列表跳过。"
      printf '\n' >&2
    fi
    printf '%s\n' "请选择要新建的 Codex 配置：" >&2
    printf '\n%s\n' "  1. 官方登录入口" >&2
    printf '%s\n' "     进入 Codex 官方登录/API Key 流程，不写第三方 provider 配置。" >&2
    printf '\n%s\n' "  2. 第三方 Responses API" >&2
    printf '%s\n' "     输入 Base URL 和 API Key，自动拉取模型。" >&2
    if [ "$all_count" -gt 0 ]; then
      printf '\n%s\n' "  3. 管理已有配置" >&2
    fi
    printf '\n%s\n' "  q. 退出，稍后继续" >&2
    printf '\n' >&2
    if [ "$all_count" -gt 0 ]; then
      mode="$(menu_read "请输入选项编号" "2" "1 2 3 q" "可选：1 / 2 / 3 / q。URL 要在选择 2 之后再填写。")"
    else
      mode="$(menu_read "请输入选项编号" "2" "1 2 q" "可选：1 / 2 / q。URL 要在选择 2 之后再填写。")"
    fi
    case "$mode" in
      1) create_official_profile; return ;;
      2)
        if create_third_party_profile; then
          return
        else
          rc="$?"
          [ "$rc" = "2" ] && continue
          exit_for_later
        fi
        ;;
      3)
        if manage_existing_profiles "$all_profiles_file" "$all_count"; then
          continue
        else
          rc="$?"
          [ "$rc" = "10" ] && return
          exit_for_later
        fi
        ;;
      q) exit_for_later ;;
    esac
  done
}

persist_path() {
  dir="$1"
  case ":${PATH:-}:" in *":$dir:"*) ;; *) export PATH="$dir:${PATH:-}" ;; esac
  mkdir -p "$HOME"
  for profile_file in "$HOME/.profile" "$HOME/.ashrc" "$HOME/.shrc"; do
    if [ ! -f "$profile_file" ] || ! grep -F "$dir" "$profile_file" >/dev/null 2>&1; then
      {
        printf '\n# codex-zh\n'
        printf 'export PATH="%s:$PATH"\n' "$dir"
      } >> "$profile_file"
    fi
  done
  if is_root && [ -d /etc/profile.d ]; then
    cat > /etc/profile.d/codex-zh.sh <<EOF
case ":\${PATH:-}:" in
  *":$dir:"*) ;;
  *) export PATH="$dir:\${PATH:-}" ;;
esac
EOF
    chmod 644 /etc/profile.d/codex-zh.sh
  fi
}

install_case_variants() {
  dir="$1"
  target="$2"
  for c in c C; do for o in o O; do for d in d D; do for e in e E; do for x in x X; do
    link="$dir/$c$o$d$e$x"
    [ "$link" = "$target" ] && continue
    ln -sf "$target" "$link" 2>/dev/null || true
  done; done; done; done; done
}

find_existing_binary() {
  for p in \
    "$REAL_BIN" \
    "$HOME/.local/bin/codex-zh-bin" \
    "/usr/local/bin/codex-zh-bin" \
    "/usr/bin/codex-zh-bin" \
    "$HOME/.cache/codex-zh/codex-${VERSION}-zh-${TARGET}" \
    "/tmp/codex-${VERSION}-zh-${TARGET}"
  do
    [ -f "$p" ] && [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

ensure_binary() {
  mkdir -p "$INSTALL_DIR"
  if [ -x "$REAL_BIN" ]; then
    return
  fi
  existing="$(find_existing_binary || true)"
  [ -n "$existing" ] || die "找不到已下载/已安装的 codex-zh-bin。这个本地续装脚本不重新下载，请先让主安装器至少完成二进制下载/解压。"
  cp "$existing" "$REAL_BIN"
  chmod 755 "$REAL_BIN"
}

write_real_wrapper() {
  real_bin_q="$(shell_quote "$REAL_BIN")"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env sh
export HOME="\${HOME:-/root}"
export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"
export PATH="\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:\${PATH:-}"
if [ ! -s "\$HOME/AGENTS.md" ] && [ -s "\$CODEX_HOME/AGENTS.md" ]; then
  cp "\$CODEX_HOME/AGENTS.md" "\$HOME/AGENTS.md" 2>/dev/null || true
fi
exec $real_bin_q "\$@"
EOF
  chmod 755 "$WRAPPER"
}

write_resume_launcher() {
  resume_q="$(shell_quote "$RESUME_SCRIPT")"
  wrapper_q="$(shell_quote "$WRAPPER")"
  cat > "$LAUNCHER" <<EOF
#!/usr/bin/env sh
export HOME="\${HOME:-/root}"
export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"
export PATH="\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:\${PATH:-}"
if [ "\${CODEX_ZH_NO_PREFLIGHT:-0}" != "1" ] && [ -x $resume_q ]; then
  CODEX_ZH_PREFLIGHT=1 $resume_q --preflight-select || exit \$?
fi
exec $wrapper_q "\$@"
EOF
  chmod 755 "$LAUNCHER"
  install_case_variants "$INSTALL_DIR" "$LAUNCHER"
}

ensure_launcher() {
  cp "$0" "$RESUME_SCRIPT" 2>/dev/null || true
  chmod 755 "$RESUME_SCRIPT" 2>/dev/null || true
  write_real_wrapper
  write_resume_launcher
  persist_path "$INSTALL_DIR"
}

check_status() {
  mkdir -p "$STATE_DIR"
  missing=0
  [ -x "$REAL_BIN" ] || { printf '%s\n' "missing_binary"; missing=1; }
  [ -x "$WRAPPER" ] || { printf '%s\n' "missing_real_wrapper"; missing=1; }
  [ -x "$LAUNCHER" ] || { printf '%s\n' "missing_launcher"; missing=1; }
  [ -s "$CODEX_HOME/AGENTS.md" ] || { printf '%s\n' "missing_agents"; missing=1; }
  last_slug="$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)"
  if [ -n "$last_slug" ] && [ -s "$CONFIGS_DIR/$last_slug/setup-mode" ] && [ "$(profile_mode "$CONFIGS_DIR/$last_slug")" = "official" ]; then
    :
  else
    [ -s "$CODEX_HOME/config.toml" ] || { printf '%s\n' "missing_config"; missing=1; }
    [ -s "$CODEX_HOME/auth.json" ] || { printf '%s\n' "missing_auth"; missing=1; }
  fi
  return "$missing"
}

configure_api_if_needed() {
  select_or_create_profile
}

run_local_setup() {
  mkdir -p "$CODEX_HOME" "$STATE_DIR"
  chmod 700 "$CODEX_HOME" "$STATE_DIR" 2>/dev/null || true
  ensure_binary
  ensure_launcher
  setup_agents_md_if_needed
  configure_api_if_needed
  info "本地续装检查完成。"
}

all_done_menu() {
  printf '%s\n' "本地安装检测已全部通过：" >&2
  printf '%s\n' "1. 清理安装脚本和临时安装状态，然后启动 Codex" >&2
  printf '%s\n' "2. 重新开始本地配置部分" >&2
  printf '%s\n' "3. 保留启动前检测，直接启动 Codex" >&2
  choice="$(tty_read "请输入选项编号" "3")"
  case "$choice" in
    1)
      rm -rf "$STATE_DIR" "$RESUME_SCRIPT" 2>/dev/null || true
      write_real_wrapper
      ln -sf "$WRAPPER" "$LAUNCHER"
      install_case_variants "$INSTALL_DIR" "$LAUNCHER"
      ;;
    2)
      rm -rf "$STATE_DIR"
      rm -f "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json"
      remove_model_catalog_files "$CODEX_HOME"
      run_local_setup
      ;;
    *) ;;
  esac
}

main() {
  [ -n "${HOME:-}" ] && [ "$HOME" != "/" ] || export HOME="/root"
  mkdir -p "$HOME"
  [ -n "$INSTALL_DIR" ] || INSTALL_DIR="$HOME/.local/bin"
  [ -n "$CODEX_HOME" ] || CODEX_HOME="$HOME/.codex"
  STATE_DIR="$CODEX_HOME/install-state"
  CONFIGS_DIR="$CODEX_HOME/api-profiles"
  LAST_PROFILE_FILE="$CONFIGS_DIR/last-profile"
  REAL_BIN="$INSTALL_DIR/codex-zh-bin"
  RESUME_SCRIPT="$INSTALL_DIR/codex-local-resume"
  LAUNCHER="$INSTALL_DIR/$INSTALL_NAME"
  WRAPPER="$INSTALL_DIR/.codex-launcher-real"
  case "${1:-}" in
    --status)
      check_status
      ;;
    --refresh-current-profile)
      refresh_current_profile
      ;;
    --preflight)
      if check_status >/dev/null 2>&1; then
        exit 0
      fi
      info "Codex 本地安装未完成，进入续装流程。"
      run_local_setup
      ;;
    --preflight-select)
      if ! check_status >/dev/null 2>&1; then
        info "Codex 本地安装未完成，进入续装流程。"
        run_local_setup
      else
        select_or_create_profile
      fi
      ;;
    *)
      if check_status >/dev/null 2>&1; then
        all_done_menu
      else
        info "检测到本地安装未完成，开始续装。"
        run_local_setup
      fi
      if [ "$SKIP_RUN" != "1" ] && [ -x "$WRAPPER" ]; then
        info "本地配置完成，正在启动 Codex..."
        export CODEX_ZH_NO_PREFLIGHT=1
        exec "$WRAPPER"
      fi
      info "完成。现在可以运行：$INSTALL_NAME"
      ;;
  esac
}

main "$@"
