# shellcheck shell=sh
[ "${CODEX_ZH_DOWNLOAD_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_DOWNLOAD_LOADED=1

codex_download_tool() {
  if codex_have curl; then
    printf '%s\n' "curl"
  elif codex_have wget; then
    printf '%s\n' "wget"
  elif codex_have busybox && busybox wget --help >/dev/null 2>&1; then
    printf '%s\n' "busybox-wget"
  else
    return 1
  fi
}

codex_download_fetch_atomic() {
  dl_url="$1"
  dl_dest="$2"
  dl_tool="$(codex_download_tool)" || codex_die "缺少 curl/wget，无法下载：$dl_url"
  dl_part="$dl_dest.part"
  mkdir -p "$(dirname "$dl_dest")"
  rm -f "$dl_part"
  if [ "$dl_tool" = "curl" ]; then
    if ! curl -fL --http1.1 \
      --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 900 \
      -o "$dl_part" "$dl_url"; then
      rm -f "$dl_part"
      return 1
    fi
  elif [ "$dl_tool" = "wget" ]; then
    if ! wget -O "$dl_part" --tries=5 --timeout=30 "$dl_url"; then
      rm -f "$dl_part"
      return 1
    fi
  else
    if ! busybox wget -O "$dl_part" "$dl_url"; then
      rm -f "$dl_part"
      return 1
    fi
  fi
  [ -s "$dl_part" ] || { rm -f "$dl_part"; return 1; }
  mv "$dl_part" "$dl_dest"
}

codex_download_script_url_candidates() {
  name="$1"
  override="${2:-}"
  [ -n "$override" ] && printf '%s\n' "$override"
  printf '%s\n' "$CODEX_ZH_SCRIPT_BASE_URL/$name"
  [ -n "$CODEX_ZH_SCRIPT_RELEASE_BASE_URL" ] && printf '%s\n' "$CODEX_ZH_SCRIPT_RELEASE_BASE_URL/$name"
}

codex_download_first_script() {
  cds_name="$1"
  cds_dest="$2"
  cds_override="${3:-}"
  cds_old_ifs="$IFS"
  IFS='
'
  for cds_url in $(codex_download_script_url_candidates "$cds_name" "$cds_override"); do
    [ -n "$cds_url" ] || continue
    codex_info "下载脚本：$cds_url"
    if codex_download_fetch_atomic "$cds_url" "$cds_dest"; then
      chmod 755 "$cds_dest" 2>/dev/null || true
      IFS="$cds_old_ifs"
      return 0
    fi
    codex_warn "下载失败：$cds_url"
    rm -f "$cds_dest.part"
  done
  IFS="$cds_old_ifs"
  return 1
}

codex_download_archive() {
  cda_url="$1"
  cda_dest="$2"
  cda_sha256="$3"
  if [ -s "$cda_dest" ]; then
    if [ "$(codex_sha256_file "$cda_dest" 2>/dev/null || true)" = "$(printf '%s' "$cda_sha256" | codex_upper)" ]; then
      codex_info "复用已校验缓存：$cda_dest"
      return 0
    fi
    codex_warn "缓存校验失败，重新下载：$cda_dest"
    rm -f "$cda_dest"
  fi
  codex_info "下载文件：$cda_url"
  codex_download_fetch_atomic "$cda_url" "$cda_dest"
  codex_verify_sha256 "$cda_dest" "$cda_sha256"
}
