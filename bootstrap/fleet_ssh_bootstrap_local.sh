#!/usr/bin/env bash
# Evergreen fleet: enable Tailscale SSH and lock sshd to tailnet interface.
set -euo pipefail

log() { printf '[fleet_ssh_bootstrap] %s\n' "$*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
  fi
}

require_root "$@"

if ! command -v tailscale >/dev/null 2>&1; then
  log "ERROR: tailscale not installed; run bootstrap/start_tailscale_cloud.sh first"
  exit 1
fi

if ! tailscale status --peers=false >/dev/null 2>&1; then
  log "ERROR: tailscale not connected"
  exit 1
fi

if ! tailscale debug prefs 2>/dev/null | grep -q '"RunSSH":true'; then
  log "Enabling Tailscale SSH"
  tailscale set --ssh
fi

TS_IP="$(tailscale ip -4 2>/dev/null || true)"
if [ -z "$TS_IP" ]; then
  log "ERROR: could not determine Tailscale IPv4"
  exit 1
fi

reload_sshd() {
  sshd -t
  if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
    return 0
  fi
  if command -v service >/dev/null 2>&1 && { service ssh reload 2>/dev/null || service sshd reload 2>/dev/null; }; then
    return 0
  fi
  local pid
  pid="$(pgrep -x sshd | head -1)" || true
  if [ -n "$pid" ] && kill -HUP "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

SSHD_DROP_IN="/etc/ssh/sshd_config.d/99-evergreen-tailscale.conf"
if [ ! -f "$SSHD_DROP_IN" ] || ! grep -qF "ListenAddress ${TS_IP}" "$SSHD_DROP_IN" 2>/dev/null; then
  log "Configuring sshd for Tailscale-only listen on $TS_IP"
  mkdir -p /etc/ssh/sshd_config.d
  cat >"$SSHD_DROP_IN" <<EOF
# Evergreen fleet: SSH via Tailscale only
ListenAddress ${TS_IP}
Port 22
PasswordAuthentication no
PermitRootLogin no
EOF
fi

if command -v sshd >/dev/null 2>&1 && [ -f "$SSHD_DROP_IN" ] && grep -qF "ListenAddress ${TS_IP}" "$SSHD_DROP_IN" 2>/dev/null; then
  if ! reload_sshd; then
    log "ERROR: failed to reload sshd"
    exit 1
  fi
fi

log "RunSSH=$(tailscale debug prefs 2>/dev/null | grep RunSSH || true)"
log "Tailscale SSH ready at ${TS_IP}"
