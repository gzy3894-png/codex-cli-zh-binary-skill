# shellcheck shell=sh
[ "${CODEX_ZH_LOCAL_LOADED:-0}" = "1" ] && return 0
CODEX_ZH_LOCAL_LOADED=1

codex_local_install_alpine_deps() {
  [ "${CODEX_ZH_SKIP_DEPS:-0}" = "1" ] && { codex_info "跳过依赖安装：CODEX_ZH_SKIP_DEPS=1"; return 0; }
  codex_have apk || { codex_warn "当前环境没有 apk，跳过 Alpine 依赖安装"; return 0; }
  profile="${CODEX_ZH_DEPS_PROFILE:-full}"
  codex_info "安装 Alpine 依赖：$profile"
  if [ "$profile" = "minimal" ]; then
    apk add --no-cache ca-certificates curl wget tar gzip git openssh-client ripgrep fd jq
  else
    apk add --no-cache \
      ca-certificates curl wget tar gzip unzip xz \
      git openssh-client ripgrep fd jq \
      python3 py3-pip nodejs npm \
      coreutils findutils sed grep gawk diffutils patch \
      bash make gcc g++ musl-dev pkgconf cmake ninja \
      openssl openssl-dev libffi-dev perl procps \
      bubblewrap 2>/dev/null || apk add --no-cache \
      ca-certificates curl wget tar gzip unzip xz git openssh-client ripgrep fd jq python3 py3-pip nodejs npm
  fi
  if ! codex_have bubblewrap && codex_have bwrap; then
    ln -sf "$(command -v bwrap)" /usr/local/bin/bubblewrap 2>/dev/null || true
  fi
}

codex_local_install_termux_deps() {
  [ "${CODEX_ZH_SKIP_DEPS:-0}" = "1" ] && { codex_info "跳过依赖安装：CODEX_ZH_SKIP_DEPS=1"; return 0; }
  [ -n "${PREFIX:-}" ] || codex_die "请在 Termux 环境运行"
  [ "$(id -u 2>/dev/null || printf 1)" != "0" ] || codex_die "不要在 Termux 的 su/root shell 里运行"
  codex_have apt-get || codex_die "缺少 apt-get/pkg"
  profile="${CODEX_ZH_DEPS_PROFILE:-full}"
  codex_info "安装 Termux 依赖：$profile"
  DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold update
  if [ "$profile" = "minimal" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold install -y ca-certificates curl wget tar gzip git openssh ripgrep jq
  else
    DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold install -y \
      ca-certificates curl wget tar gzip unzip xz-utils \
      git openssh ripgrep fd jq \
      python nodejs npm \
      coreutils findutils sed grep gawk diffutils patch \
      bash make clang binutils lld pkg-config cmake ninja \
      openssl libffi perl procps proot
  fi
}

codex_local_extract_binary_from_archive() {
  archive="$1"
  out_bin="$2"
  work="$(codex_state_root)/extract-binary"
  rm -rf "$work"
  mkdir -p "$work"
  tar -xzf "$archive" -C "$work"
  src=""
  for candidate in \
    "$work/codex-${CODEX_ZH_VERSION}-zh-${CODEX_ZH_TARGET}" \
    "$work/codex" \
    "$work/codex-zh-bin"
  do
    [ -f "$candidate" ] && { src="$candidate"; break; }
  done
  if [ -z "$src" ]; then
    src="$(find "$work" -type f -perm -u+x -name 'codex*' 2>/dev/null | sed -n '1p')"
  fi
  [ -n "$src" ] || codex_die "压缩包中没有找到 Codex 二进制"
  codex_verify_sha256 "$src" "$CODEX_ZH_BIN_SHA256"
  mkdir -p "$(dirname "$out_bin")"
  cp "$src" "$out_bin"
  chmod 755 "$out_bin"
  rm -rf "$work"
}

codex_local_install_binary() {
  install_dir="$(codex_install_dir)"
  real_bin="$(codex_real_bin_path)"
  mkdir -p "$install_dir"
  if [ -x "$real_bin" ] && [ "$(codex_sha256_file "$real_bin" 2>/dev/null || true)" = "$(printf '%s' "$CODEX_ZH_BIN_SHA256" | codex_upper)" ]; then
    codex_info "Codex 二进制已存在并通过校验：$real_bin"
    return 0
  fi
  cache="$(codex_cache_root)"
  mkdir -p "$cache"
  archive="$cache/$CODEX_ZH_ARCHIVE"
  archive_url="${CODEX_ZH_ARCHIVE_URL:-$CODEX_ZH_BINARY_BASE_URL/$CODEX_ZH_ARCHIVE}"
  codex_download_archive "$archive_url" "$archive" "$CODEX_ZH_ARCHIVE_SHA256"
  codex_local_extract_binary_from_archive "$archive" "$real_bin"
}

codex_local_write_launcher() {
  install_dir="$(codex_install_dir)"
  real_bin="$(codex_real_bin_path)"
  launcher="$(codex_launcher_path)"
  mkdir -p "$install_dir"
  [ -x "$real_bin" ] || codex_die "缺少 Codex 二进制：$real_bin"
  real_q="$(codex_shell_quote "$real_bin")"
  {
    printf '%s\n' '#!/usr/bin/env sh'
    printf 'real_bin=%s\n' "$real_q"
    cat <<'EOF'
export HOME="${HOME:-/root}"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

codex_for_tui_find_lib_dir() {
  for dir in \
    "${CODEX_ZH_SCRIPT_INSTALL_ROOT:-}/lib" \
    "$(dirname -- "$0")/../share/codex-zh/scripts/lib" \
    "$HOME/.local/share/codex-zh/scripts/lib" \
    "/usr/local/share/codex-zh/scripts/lib" \
    "$HOME/.cache/codex-zh/scripts/lib"
  do
    [ -r "$dir/codex-zh-common.sh" ] && { printf '%s\n' "$dir"; return 0; }
  done
  return 1
}

codex_for_tui_load_config_libs() {
  lib_dir="$(codex_for_tui_find_lib_dir)" || {
    printf '%s\n' "错误: 找不到 codex-zh 配置模块。请先运行 codex 更新。" >&2
    exit 1
  }
  # shellcheck disable=SC1090
  . "$lib_dir/codex-zh-common.sh"
  # shellcheck disable=SC1090
  . "$lib_dir/codex-zh-config.sh"
  # shellcheck disable=SC1090
  . "$lib_dir/codex-zh-local.sh"
}

codex_for_tui_has_config() {
  [ -s "$CODEX_HOME/config.toml" ] && return 0
  [ -s "$CODEX_HOME/auth.json" ] && return 0
  [ -s "$CODEX_HOME/install-state/official-login-mode" ] && return 0
  return 1
}

codex_for_tui_configure_if_missing() {
  codex_for_tui_has_config && return 0
  codex_for_tui_load_config_libs
  codex_init_env
  codex_local_configure_if_requested
}

codex_for_tui_force_configure() {
  codex_for_tui_load_config_libs
  codex_init_env
  codex_config_prompt_third_party
}

codex_for_tui_update() {
  if command -v codex-update >/dev/null 2>&1; then
    [ "$#" -gt 0 ] || set -- apply
    exec codex-update "$@"
  fi
  printf '%s\n' "错误: 找不到 codex-update。请先确认 Codex for TUI 安装完整。" >&2
  exit 1
}

case "${1:-}" in
  配置模式|configure|config)
    shift
    codex_for_tui_force_configure
    exec "$real_bin" "$@"
    ;;
  更新|update)
    shift
    codex_for_tui_update "$@"
    ;;
esac

if [ ! -s "$HOME/AGENTS.md" ] && [ -s "$CODEX_HOME/AGENTS.md" ]; then
  cp "$CODEX_HOME/AGENTS.md" "$HOME/AGENTS.md" 2>/dev/null || true
fi

codex_for_tui_configure_if_missing
exec "$real_bin" "$@"
EOF
  } > "$launcher"
  chmod 755 "$launcher"
  codex_install_case_variants "$install_dir" "$launcher"
  codex_persist_path "$install_dir"
}

codex_local_copy_if_present() {
  src="$1"
  dest="$2"
  [ -r "$src" ] || return 1
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  chmod 755 "$dest" 2>/dev/null || true
}

codex_local_install_support_scripts() {
  install_dir="$(codex_install_dir)"
  dest_root="$(codex_script_install_root)"
  src_root="${CODEX_ZH_ACTIVE_SCRIPT_DIR:-}"
  cache_root="$(codex_script_cache_root)"
  mkdir -p "$dest_root/lib" "$install_dir"

  for root in "$src_root" "$cache_root"; do
    [ -n "$root" ] || continue
    [ -d "$root/lib" ] || continue
    for file in "$root"/lib/*.sh; do
      [ -f "$file" ] || continue
      cp "$file" "$dest_root/lib/$(basename "$file")"
      chmod 644 "$dest_root/lib/$(basename "$file")" 2>/dev/null || true
    done
    for name in codex-local-resume.sh codex-update.sh codex-for-tui-bootstrap.sh install-reterminal-alpine.sh install-alpine-proot.sh install.sh; do
      [ -f "$root/$name" ] || continue
      cp "$root/$name" "$dest_root/$name"
      chmod 755 "$dest_root/$name" 2>/dev/null || true
    done
    break
  done

  [ -s "$dest_root/codex-local-resume.sh" ] && cp "$dest_root/codex-local-resume.sh" "$install_dir/codex-local-resume" && chmod 755 "$install_dir/codex-local-resume"
  [ -s "$dest_root/codex-local-resume.sh" ] && cp "$dest_root/codex-local-resume.sh" "$install_dir/codex-local" && chmod 755 "$install_dir/codex-local"
  [ -s "$dest_root/codex-update.sh" ] && cp "$dest_root/codex-update.sh" "$install_dir/codex-update" && chmod 755 "$install_dir/codex-update"
  [ -s "$dest_root/codex-for-tui-bootstrap.sh" ] && cp "$dest_root/codex-for-tui-bootstrap.sh" "$install_dir/codex-for-tui-bootstrap" && chmod 755 "$install_dir/codex-for-tui-bootstrap"
}

codex_local_setup_agents() {
  home_dir="$(codex_home)"
  codex_ensure_private_dir "$home_dir"
  [ -s "$home_dir/AGENTS.md" ] && return 0
  cat > "$home_dir/AGENTS.md" <<'EOF'
# Codex for TUI

你运行在 Android/Alpine 终端环境中。默认使用用户当前工作目录和 ~/.codex/config.toml。
普通启动不自动更新脚本，不自动刷新模型，不覆盖用户手写配置。
需要更新脚本时手动运行 codex-update；需要刷新第三方模型目录时手动运行 codex-local refresh-models。
EOF
  chmod 600 "$home_dir/AGENTS.md" 2>/dev/null || true
}

codex_local_configure_if_requested() {
  [ "${CODEX_ZH_SKIP_API_SETUP:-0}" = "1" ] && { codex_info "跳过 API 配置：CODEX_ZH_SKIP_API_SETUP=1"; return 0; }
  if codex_config_has_runtime_config && [ "${CODEX_ZH_OVERWRITE_CONFIG:-0}" != "1" ]; then
    codex_info "检测到已有 Codex 配置或官方登录模式，保留现状。"
    return 0
  fi
  if [ "${CODEX_ZH_SETUP_MODE:-}" = "official" ]; then
    codex_info "使用官方 Codex 登录入口；不写第三方 provider 配置。"
    codex_config_mark_official_mode
    return 0
  fi
  if [ "${CODEX_ZH_SETUP_MODE:-}" = "third_party" ] || [ -n "${CODEX_ZH_API_BASE:-}" ] || [ -n "${CODEX_ZH_API_KEY:-}" ]; then
    codex_config_prompt_third_party
    return 0
  fi
  printf '%s\n' "请选择 Codex 初始化方式：" >&2
  printf '%s\n' "1. 官方登录入口：不写第三方 provider 配置" >&2
  printf '%s\n' "2. 第三方 Responses API：输入 Base URL 和 API Key，显式生成配置" >&2
  choice="$(codex_config_tty_read "请输入选项编号" "1")"
  case "$choice" in
    2) codex_config_prompt_third_party ;;
    *)
      codex_info "使用官方 Codex 登录入口；不写第三方 provider 配置。"
      codex_config_mark_official_mode
      ;;
  esac
}

codex_local_install_reterminal() {
  codex_init_env
  codex_local_install_alpine_deps
  codex_local_install_binary
  codex_local_write_launcher
  codex_local_install_support_scripts
  codex_local_setup_agents
  codex_local_configure_if_requested
  codex_info "安装完成：$(codex_launcher_path)"
  if [ "${CODEX_ZH_SKIP_RUN:-0}" != "1" ]; then
    exec "$(codex_launcher_path)"
  fi
}

codex_local_install_native_termux() {
  codex_init_env
  codex_local_install_termux_deps
  codex_local_install_binary
  codex_local_write_launcher
  codex_local_install_support_scripts
  codex_local_setup_agents
  codex_local_configure_if_requested
  codex_info "安装完成：$(codex_launcher_path)"
  if [ "${CODEX_ZH_SKIP_RUN:-0}" != "1" ]; then
    exec "$(codex_launcher_path)"
  fi
}

codex_local_proot_exec() {
  rootfs="$1"
  shift
  proot -0 --link2symlink -r "$rootfs" \
    -b /dev -b /proc -b /sys \
    -b "$HOME:/termux-home" \
    -w /root /usr/bin/env -i HOME=/root PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin "$@"
}

codex_local_materialize_script_tree() {
  out_root="$1"
  src_root="${CODEX_ZH_ACTIVE_SCRIPT_DIR:-}"
  mkdir -p "$out_root/lib"
  for rel in \
    lib/codex-zh-common.sh \
    lib/codex-zh-download.sh \
    lib/codex-zh-config.sh \
    lib/codex-zh-local.sh \
    lib/codex-zh-update.sh \
    codex-local-resume.sh \
    codex-update.sh \
    codex-for-tui-bootstrap.sh \
    install-reterminal-alpine.sh \
    install-alpine-proot.sh \
    install.sh
  do
    if [ -n "$src_root" ] && [ -r "$src_root/$rel" ]; then
      mkdir -p "$(dirname "$out_root/$rel")"
      cp "$src_root/$rel" "$out_root/$rel"
    else
      codex_download_first_script "$rel" "$out_root/$rel" ""
    fi
    case "$rel" in
      *.sh) chmod 755 "$out_root/$rel" 2>/dev/null || true ;;
    esac
  done
}

codex_local_copy_tree() {
  src_root="$1"
  dest_root="$2"
  rm -rf "$dest_root"
  mkdir -p "$dest_root/lib"
  for rel in \
    lib/codex-zh-common.sh \
    lib/codex-zh-download.sh \
    lib/codex-zh-config.sh \
    lib/codex-zh-local.sh \
    lib/codex-zh-update.sh \
    codex-local-resume.sh \
    codex-update.sh \
    codex-for-tui-bootstrap.sh \
    install-reterminal-alpine.sh \
    install-alpine-proot.sh \
    install.sh
  do
    [ -r "$src_root/$rel" ] || codex_die "缺少脚本文件：$src_root/$rel"
    mkdir -p "$(dirname "$dest_root/$rel")"
    cp "$src_root/$rel" "$dest_root/$rel"
    case "$rel" in
      *.sh) chmod 755 "$dest_root/$rel" 2>/dev/null || true ;;
    esac
  done
}

codex_local_run_rootfs_installer() {
  rootfs="$1"
  script_path="/root/codex-zh-scripts/install-reterminal-alpine.sh"
  codex_local_proot_exec "$rootfs" \
    CODEX_ZH_VERSION="$CODEX_ZH_VERSION" \
    CODEX_ZH_TARGET="$CODEX_ZH_TARGET" \
    CODEX_ZH_BRANCH="$CODEX_ZH_BRANCH" \
    CODEX_ZH_REPO_RAW="$CODEX_ZH_REPO_RAW" \
    CODEX_ZH_SCRIPT_BASE_URL="$CODEX_ZH_SCRIPT_BASE_URL" \
    CODEX_ZH_SCRIPT_RELEASE_BASE_URL="$CODEX_ZH_SCRIPT_RELEASE_BASE_URL" \
    CODEX_ZH_BINARY_BASE_URL="$CODEX_ZH_BINARY_BASE_URL" \
    CODEX_ZH_ARCHIVE_SHA256="$CODEX_ZH_ARCHIVE_SHA256" \
    CODEX_ZH_BIN_SHA256="$CODEX_ZH_BIN_SHA256" \
    CODEX_ZH_PROVIDER_ID="$CODEX_ZH_PROVIDER_ID" \
    CODEX_ZH_INSTALL_NAME="$CODEX_ZH_INSTALL_NAME" \
    CODEX_ZH_DEPS_PROFILE="${CODEX_ZH_DEPS_PROFILE:-full}" \
    CODEX_ZH_SKIP_DEPS="${CODEX_ZH_SKIP_ALPINE_DEPS:-${CODEX_ZH_SKIP_DEPS:-0}}" \
    CODEX_ZH_SKIP_API_SETUP="${CODEX_ZH_SKIP_API_SETUP:-0}" \
    CODEX_ZH_SETUP_MODE="${CODEX_ZH_SETUP_MODE:-}" \
    CODEX_ZH_API_BASE="${CODEX_ZH_API_BASE:-}" \
    CODEX_ZH_API_KEY="${CODEX_ZH_API_KEY:-}" \
    CODEX_ZH_DEFAULT_MODEL="${CODEX_ZH_DEFAULT_MODEL:-}" \
    CODEX_ZH_OVERWRITE_CONFIG="${CODEX_ZH_OVERWRITE_CONFIG:-0}" \
    CODEX_ZH_FORCE_STDIN="${CODEX_ZH_FORCE_STDIN:-0}" \
    CODEX_ZH_SKIP_RUN=1 \
    sh "$script_path"
}

codex_local_write_proot_launcher() {
  path="$1"
  rootfs="$2"
  rootfs_q="$(codex_shell_quote "$rootfs")"
  cat > "$path" <<EOF
#!/usr/bin/env sh
rootfs=$rootfs_q
exec proot -0 --link2symlink -r "\$rootfs" \\
  -b /dev -b /proc -b /sys -b "\$HOME:/termux-home" \\
  -w /root /usr/bin/env -i \\
  HOME=/root USER=root LOGNAME=root TERM="\${TERM:-xterm-256color}" \\
  PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin \\
  /root/.local/bin/codex "\$@"
EOF
  chmod 755 "$path"
}

codex_local_install_alpine_proot() {
  codex_init_env
  old_deps_profile="${CODEX_ZH_DEPS_PROFILE+x}${CODEX_ZH_DEPS_PROFILE:-}"
  CODEX_ZH_DEPS_PROFILE="${CODEX_ZH_TERMUX_DEPS_PROFILE:-minimal}"
  codex_local_install_termux_deps
  if [ -n "$old_deps_profile" ]; then
    CODEX_ZH_DEPS_PROFILE="${old_deps_profile#x}"
  else
    unset CODEX_ZH_DEPS_PROFILE
  fi
  root_base="${CODEX_ZH_ALPINE_ROOT_BASE:-${PREFIX:-$HOME}/var/lib/codex-zh/codex-alpine}"
  rootfs="$root_base/rootfs"
  cache="$(codex_cache_root)"
  alpine_version="${CODEX_ZH_ALPINE_VERSION:-3.24.1}"
  alpine_name="alpine-minirootfs-${alpine_version}-aarch64.tar.gz"
  alpine_url="${CODEX_ZH_ALPINE_URL:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/$alpine_name}"
  alpine_sha="${CODEX_ZH_ALPINE_SHA256:-F55A90F69052C5BD6F92CB09A8F47065970830B194C917A006FB94028E721259}"
  mkdir -p "$root_base" "$cache"
  if [ ! -s "$rootfs/etc/alpine-release" ]; then
    archive="$cache/$alpine_name"
    codex_download_archive "$alpine_url" "$archive" "$alpine_sha"
    rm -rf "$rootfs"
    mkdir -p "$rootfs"
    tar -xzf "$archive" -C "$rootfs"
  fi
  scripts_work="$(codex_state_root)/proot-scripts"
  codex_local_materialize_script_tree "$scripts_work"
  codex_local_copy_tree "$scripts_work" "$rootfs/root/codex-zh-scripts"
  codex_local_run_rootfs_installer "$rootfs"

  launcher_dir="${PREFIX:-$HOME/.local}/bin"
  mkdir -p "$launcher_dir"
  codex_local_write_proot_launcher "$launcher_dir/codex-alpine" "$rootfs"
  ln -sf "$launcher_dir/codex-alpine" "$launcher_dir/$CODEX_ZH_INSTALL_NAME" 2>/dev/null || true
  codex_info "Alpine proot 和 Codex 已安装：$rootfs"
  codex_info "入口：$launcher_dir/codex-alpine"
  if [ "${CODEX_ZH_SKIP_RUN:-0}" != "1" ]; then
    "$launcher_dir/codex-alpine" --version
  fi
}

codex_local_status() {
  missing=0
  [ -x "$(codex_real_bin_path)" ] || { printf '%s\n' "missing_binary"; missing=1; }
  [ -x "$(codex_launcher_path)" ] || { printf '%s\n' "missing_launcher"; missing=1; }
  [ -s "$(codex_home)/AGENTS.md" ] || { printf '%s\n' "missing_agents"; missing=1; }
  if [ -s "$(codex_config_file)" ]; then
    :
  else
    printf '%s\n' "missing_config_or_official_login"
  fi
  return "$missing"
}

codex_local_doctor() {
  if codex_local_status; then
    codex_info "本地安装核心文件完整。"
  else
    codex_warn "本地安装不完整；可运行 codex-local repair-launcher 或重新执行安装脚本。"
    return 1
  fi
}

codex_local_repair_launcher() {
  codex_init_env
  codex_local_write_launcher
  codex_local_install_support_scripts
  codex_info "已修复启动器：$(codex_launcher_path)"
}

codex_local_run() {
  codex_init_env
  [ -x "$(codex_launcher_path)" ] || codex_die "缺少启动器：$(codex_launcher_path)"
  exec "$(codex_launcher_path)" "$@"
}
