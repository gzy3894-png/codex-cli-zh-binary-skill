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
ALLOW_MANUAL_MODEL="${CODEX_ZH_ALLOW_MANUAL_MODEL:-0}"
SKIP_RUN="${CODEX_ZH_SKIP_RUN:-0}"

info() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
lower() { tr '[:upper:]' '[:lower:]'; }
tty_available() {
  [ "${CODEX_ZH_FORCE_STDIN:-0}" = "1" ] && return 1
  [ -r /dev/tty ] && [ -w /dev/tty ] && { : < /dev/tty; } 2>/dev/null
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

normalize_api_base() {
  printf '%s' "$1" | sed 's/[[:space:]]//g; s#/*$##' | awk '
    /\/v1$/ { print; next }
    { print $0 "/v1" }
  '
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
    printf '\n%s\n' "选择要启用的模型（默认已全选）：" >&2
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
        printf '%s\n' "已清空选择。请至少选择一个模型，或继续按回车使用全部模型兜底。" >&2
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
    warn "未选择任何模型，默认启用全部模型。"
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
  printf '%s\n' "这个模型会写入 config.toml 的 model 字段，Codex 启动后会默认使用它；其他已启用模型仍可在 /model 中切换。" >&2
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

write_model_catalog_entry() {
  model_name="$1"
  priority="$2"
  need_comma="$3"
  model_name_esc="$(json_escape "$model_name")"

  [ "$need_comma" = "1" ] && printf ',\n'
  printf '    {\n'
  printf '      "slug": "%s",\n' "$model_name_esc"
  printf '      "display_name": "%s",\n' "$model_name_esc"
  printf '      "description": "Third-party API model",\n'
  printf '      "default_reasoning_level": "medium",\n'
  printf '      "supported_reasoning_levels": [\n'
  printf '        {"effort": "low", "description": "Fast responses with lighter reasoning"},\n'
  printf '        {"effort": "medium", "description": "Balances speed and reasoning depth"},\n'
  printf '        {"effort": "high", "description": "Greater reasoning depth"},\n'
  printf '        {"effort": "xhigh", "description": "Extra high reasoning depth"}\n'
  printf '      ],\n'
  printf '      "shell_type": "shell_command",\n'
  printf '      "visibility": "list",\n'
  printf '      "supported_in_api": true,\n'
  printf '      "priority": %s,\n' "$priority"
  printf '      "availability_nux": null,\n'
  printf '      "upgrade": null,\n'
  printf '      "base_instructions": "",\n'
  printf '      "model_messages": null,\n'
  printf '      "supports_reasoning_summaries": true,\n'
  printf '      "default_reasoning_summary": "auto",\n'
  printf '      "support_verbosity": false,\n'
  printf '      "default_verbosity": null,\n'
  printf '      "apply_patch_tool_type": null,\n'
  printf '      "web_search_tool_type": "text",\n'
  printf '      "truncation_policy": {"mode": "tokens", "limit": 10000},\n'
  printf '      "supports_parallel_tool_calls": true,\n'
  printf '      "supports_image_detail_original": false,\n'
  printf '      "context_window": 120000,\n'
  printf '      "max_context_window": 120000,\n'
  printf '      "auto_compact_token_limit": null,\n'
  printf '      "effective_context_window_percent": 95,\n'
  printf '      "experimental_supported_tools": [],\n'
  printf '      "input_modalities": ["text"],\n'
  printf '      "supports_search_tool": false,\n'
  printf '      "use_responses_lite": false\n'
  printf '    }'
}

write_model_catalog_json() {
  catalog_file="$1"
  enabled_file="$2"
  default_model="$3"

  first=1
  priority=0
  {
    printf '{\n'
    printf '  "models": [\n'
    if [ -n "$default_model" ]; then
      write_model_catalog_entry "$default_model" "$priority" "0"
      first=0
      priority=$((priority + 10))
    fi
    if [ -s "$enabled_file" ]; then
      while IFS= read -r model_name; do
        [ -n "$model_name" ] || continue
        [ "$model_name" = "$default_model" ] && continue
        if [ "$first" -eq 1 ]; then need_comma=0; first=0; else need_comma=1; fi
        write_model_catalog_entry "$model_name" "$priority" "$need_comma"
        priority=$((priority + 10))
      done < "$enabled_file"
    fi
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } > "$catalog_file"
  chmod 600 "$catalog_file"
}

write_codex_config() {
  api_base="$1"
  api_key="$2"
  default_model="$3"
  enabled_file="$4"
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

  catalog_file="$out_home/model-catalog.json"
  write_model_catalog_json "$catalog_file" "$enabled_file" "$default_model"

  config_file="$out_home/config.toml"
  provider_id_esc="$(toml_escape "$PROVIDER_ID")"
  default_model_esc="$(toml_escape "$default_model")"
  api_base_esc="$(toml_escape "$api_base")"
  home_esc="$(toml_escape "$HOME")"
  catalog_file_esc="$(toml_escape "$catalog_file")"
  {
    printf 'model_provider = "%s"\n' "$provider_id_esc"
    printf 'model = "%s"\n' "$default_model_esc"
    printf 'model_catalog_json = "%s"\n' "$catalog_file_esc"
    printf 'model_reasoning_effort = "medium"\n'
    printf 'model_auto_compact_token_limit = 120000\n'
    printf 'disable_response_storage = true\n'
    printf '\n[features]\n'
    printf 'hooks = false\n'
    printf '\n[model_providers.%s]\n' "$PROVIDER_ID"
    printf 'name = "%s"\n' "$provider_id_esc"
    printf 'base_url = "%s"\n' "$api_base_esc"
    printf 'wire_api = "responses"\n'
    printf 'requires_openai_auth = true\n'
    printf '\n[projects."%s"]\n' "$home_esc"
    printf 'trust_level = "trusted"\n'
    printf '\n[tui]\n'
    printf 'status_line = ["model-with-reasoning", "current-dir", "context-remaining"]\n'
    printf 'status_line_use_colors = true\n'
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

  info "配置启动提示词 AGENTS.md"
  printf '%s\n' "请选择启动提示词：" >&2
  printf '%s\n' "1. 默认 AGENTS.md：生成标准版系统提示词，每次启动自动带上" >&2
  printf '%s\n' "2. 自定义 AGENTS.md：现在粘贴你的内容" >&2
  choice="$(tty_read "请输入选项编号" "1")"
  choice_lc="$(printf '%s' "$choice" | lower)"
  case "$choice_lc" in
    2|custom|自定义)
      info "请输入自定义 AGENTS.md 内容。单独输入一行 EOF 结束。"
      : > "$agents_file"
      while :; do
        if tty_available; then IFS= read -r line < /dev/tty || break; else IFS= read -r line || break; fi
        [ "$line" = "EOF" ] && break
        printf '%s\n' "$line" >> "$agents_file"
      done
      [ -s "$agents_file" ] || write_standard_agents "$agents_file"
      ;;
    *) write_standard_agents "$agents_file" ;;
  esac
  cp "$agents_file" "$home_agents" 2>/dev/null || true
  chmod 600 "$agents_file" "$home_agents" 2>/dev/null || true
}

apply_profile() {
  profile_dir="$1"
  [ -d "$profile_dir" ] || die "配置不存在：$profile_dir"
  if [ -s "$profile_dir/setup-mode" ] && [ "$(sed -n '1p' "$profile_dir/setup-mode")" = "official" ]; then
    if [ ! -s "$LAST_PROFILE_FILE" ] && { [ -s "$CODEX_HOME/config.toml" ] || [ -s "$CODEX_HOME/auth.json" ] || [ -s "$CODEX_HOME/model-catalog.json" ]; }; then
      ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo legacy)"
      backup_dir="$CONFIGS_DIR/imported-before-official-$ts"
      mkdir -p "$backup_dir"
      printf '%s\n' "切换官方前自动备份" > "$backup_dir/name"
      printf '%s\n' "third_party" > "$backup_dir/setup-mode"
      [ ! -s "$CODEX_HOME/config.toml" ] || cp "$CODEX_HOME/config.toml" "$backup_dir/config.toml"
      [ ! -s "$CODEX_HOME/auth.json" ] || cp "$CODEX_HOME/auth.json" "$backup_dir/auth.json"
      [ ! -s "$CODEX_HOME/model-catalog.json" ] || cp "$CODEX_HOME/model-catalog.json" "$backup_dir/model-catalog.json"
      chmod 700 "$backup_dir" 2>/dev/null || true
      chmod 600 "$backup_dir/config.toml" "$backup_dir/auth.json" "$backup_dir/model-catalog.json" 2>/dev/null || true
      warn "已先把当前 ~/.codex 配置备份为：$backup_dir"
    fi
    rm -f "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json" "$CODEX_HOME/model-catalog.json"
    [ ! -s "$profile_dir/config.toml" ] || cp "$profile_dir/config.toml" "$CODEX_HOME/config.toml"
    [ ! -s "$profile_dir/auth.json" ] || cp "$profile_dir/auth.json" "$CODEX_HOME/auth.json"
    [ ! -s "$profile_dir/model-catalog.json" ] || cp "$profile_dir/model-catalog.json" "$CODEX_HOME/model-catalog.json"
    chmod 600 "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json" "$CODEX_HOME/model-catalog.json" 2>/dev/null || true
  else
    [ -s "$profile_dir/config.toml" ] || die "配置缺少 config.toml：$profile_dir"
    [ -s "$profile_dir/auth.json" ] || die "配置缺少 auth.json：$profile_dir"
    [ -s "$profile_dir/model-catalog.json" ] || die "配置缺少 model-catalog.json：$profile_dir"
    cp "$profile_dir/config.toml" "$CODEX_HOME/config.toml"
    cp "$profile_dir/auth.json" "$CODEX_HOME/auth.json"
    cp "$profile_dir/model-catalog.json" "$CODEX_HOME/model-catalog.json"
    chmod 600 "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json" "$CODEX_HOME/model-catalog.json" 2>/dev/null || true
  fi
  basename "$profile_dir" > "$LAST_PROFILE_FILE"
  profile_label "$profile_dir" > "$STATE_DIR/active-profile-label"
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
      [ ! -s "$CODEX_HOME/model-catalog.json" ] || cp "$CODEX_HOME/model-catalog.json" "$profile_dir/model-catalog.json"
      ;;
    third_party)
      [ ! -s "$CODEX_HOME/config.toml" ] || cp "$CODEX_HOME/config.toml" "$profile_dir/config.toml"
      [ ! -s "$CODEX_HOME/auth.json" ] || cp "$CODEX_HOME/auth.json" "$profile_dir/auth.json"
      [ ! -s "$CODEX_HOME/model-catalog.json" ] || cp "$CODEX_HOME/model-catalog.json" "$profile_dir/model-catalog.json"
      ;;
  esac
  chmod 600 "$profile_dir/config.toml" "$profile_dir/auth.json" "$profile_dir/model-catalog.json" 2>/dev/null || true
}

fetch_models_or_prompt() {
  api_base="$1"
  api_key="$2"
  models_file="$3"
  models_json="$4"
  models_err="$5"

  while :; do
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
    printf '%s\n' "1. 重试获取模型列表" >&2
    printf '%s\n' "2. 重新填写 API Base URL 和 API Key" >&2
    printf '%s\n' "3. 退出，稍后再运行 codex 继续" >&2
    choice="$(tty_read "请输入选项编号" "2")"
    case "$(printf '%s' "$choice" | lower)" in
      1|retry|重试) ;;
      2|refill|重新填写|重填) return 2 ;;
      *) return 1 ;;
    esac
  done
}

create_official_profile() {
  profile_dir="$CONFIGS_DIR/official"
  mkdir -p "$profile_dir"
  printf '%s\n' "官方登录入口" > "$profile_dir/name"
  printf '%s\n' "official" > "$profile_dir/setup-mode"
  apply_profile "$profile_dir"
}

create_third_party_profile() {
  work_dir="$STATE_DIR/new-profile"
  rm -rf "$work_dir"
  mkdir -p "$work_dir"

  while :; do
    raw_base="${CODEX_ZH_API_BASE:-}"
    api_key="${CODEX_ZH_API_KEY:-}"
    [ -n "$raw_base" ] || raw_base="$(tty_read "请输入 API Base URL，例如 https://api.example.com 或 https://api.example.com/v1" "")"
    [ -n "$api_key" ] || api_key="$(tty_read_api_key "请输入 API Key")"
    [ -n "$raw_base" ] || die "API Base URL 不能为空"
    [ -n "$api_key" ] || die "API Key 不能为空"
    api_base="$(normalize_api_base "$raw_base")"
    info "规范化后的 API Base URL: $api_base"

    models_file="$work_dir/models.txt"
    models_json="$work_dir/models.json"
    models_err="$work_dir/models.err"
    if fetch_models_or_prompt "$api_base" "$api_key" "$models_file" "$models_json" "$models_err"; then
      break
    else
      rc="$?"
    fi
    [ "$rc" = "2" ] || return 1
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
  write_codex_config "$api_base" "$api_key" "$default_model" "$enabled_file" "$profile_dir"
  apply_profile "$profile_dir"
}

select_or_create_profile() {
  mkdir -p "$CONFIGS_DIR" "$STATE_DIR"
  chmod 700 "$CONFIGS_DIR" "$STATE_DIR" 2>/dev/null || true
  sync_current_profile

  profiles_file="$STATE_DIR/profiles.txt"
  : > "$profiles_file"
  for d in "$CONFIGS_DIR"/*; do
    [ -d "$d" ] || continue
    [ -s "$d/setup-mode" ] || continue
    printf '%s\n' "$d" >> "$profiles_file"
  done

  last_slug="$(sed -n '1p' "$LAST_PROFILE_FILE" 2>/dev/null || true)"
  default_choice=""
  count="$(wc -l < "$profiles_file" | tr -d ' ')"
  if [ "$count" -gt 0 ]; then
    printf '\n%s\n' "请选择本次启动使用的 Codex 配置：" >&2
    i=1
    while [ "$i" -le "$count" ]; do
      d="$(sed -n "${i}p" "$profiles_file")"
      label="$(profile_label "$d")"
      mode="$(sed -n '1p' "$d/setup-mode" 2>/dev/null || true)"
      mark=""
      if [ "$(basename "$d")" = "$last_slug" ]; then
        mark="（上次使用）"
        default_choice="$i"
      fi
      printf '%2s. %s [%s] %s\n' "$i" "$label" "$mode" "$mark" >&2
      i=$((i + 1))
    done
    new_choice=$((count + 1))
    printf '%2s. 新建配置\n' "$new_choice" >&2
    [ -n "$default_choice" ] || default_choice="$new_choice"
    choice="$(tty_read "请输入选项编号" "$default_choice")"
    case "$choice" in
      *[!0-9]*|"") choice="$default_choice" ;;
    esac
    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ] 2>/dev/null; then
      apply_profile "$(sed -n "${choice}p" "$profiles_file")"
      return
    fi
  fi

  printf '%s\n' "请选择要新建的 Codex 配置：" >&2
  printf '%s\n' "1. 官方登录入口：进入 Codex 官方登录/API Key 流程，不写第三方 provider 配置" >&2
  printf '%s\n' "2. 第三方 Responses API：输入 Base URL 和 API Key，自动拉取模型" >&2
  mode="$(tty_read "请输入选项编号" "2")"
  case "$(printf '%s' "$mode" | lower)" in
    1|official|官方) create_official_profile ;;
    *) create_third_party_profile ;;
  esac
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
  if [ "$(id -u)" = "0" ] && [ -d /etc/profile.d ]; then
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
  if [ -n "$last_slug" ] && [ -s "$CONFIGS_DIR/$last_slug/setup-mode" ] && [ "$(sed -n '1p' "$CONFIGS_DIR/$last_slug/setup-mode")" = "official" ]; then
    :
  else
    [ -s "$CODEX_HOME/config.toml" ] || { printf '%s\n' "missing_config"; missing=1; }
    [ -s "$CODEX_HOME/auth.json" ] || { printf '%s\n' "missing_auth"; missing=1; }
    [ -s "$CODEX_HOME/model-catalog.json" ] || { printf '%s\n' "missing_model_catalog"; missing=1; }
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
      rm -f "$CODEX_HOME/config.toml" "$CODEX_HOME/auth.json" "$CODEX_HOME/model-catalog.json"
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
