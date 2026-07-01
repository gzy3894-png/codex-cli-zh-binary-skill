#!/usr/bin/env sh
set -e

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/system/bin:/system/xbin:${PATH:-}
export HOME="${HOME:-/root}"
export PIP_BREAK_SYSTEM_PACKAGES=1
export PS1='\[\033[01;32m\]\u@codex-tui\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

if [ ! -s /etc/resolv.conf ]; then
  echo "nameserver 8.8.8.8" > /etc/resolv.conf 2>/dev/null || true
fi

if [ ! -f /linkerconfig/ld.config.txt ]; then
  mkdir -p /linkerconfig 2>/dev/null || true
  : > /linkerconfig/ld.config.txt 2>/dev/null || true
fi

if [ "$#" -eq 0 ]; then
  [ ! -r /etc/profile ] || . /etc/profile
  cd "$HOME" 2>/dev/null || true
  if [ -s "${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin/codex-for-tui-bootstrap.sh" ]; then
    sh "${PREFIX:-/data/data/com.gzy3894.codexfortui/files}/local/bin/codex-for-tui-bootstrap.sh" || echo "警告: Codex for TUI 启动失败，已回到 shell。"
  fi
  exec /bin/ash
fi

exec "$@"
