#!/usr/bin/env bash
# Evergreen fleet: install Tailscale and join tailnet on cloud agents.
set -euo pipefail

log() { printf '[start_tailscale_cloud] %s\n' "$*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

resolve_auth_key() {
  python3 "${SCRIPT_DIR}/resolve_tailscale_auth_key.py"
}

# Resolve before sudo: Cursor injects display names with spaces that sudo may drop.
AUTH_KEY="$(resolve_auth_key)"
export TAILSCALE_AUTHKEY="${AUTH_KEY}"
export TAILSCALE_AUTH_KEY="${AUTH_KEY}"

tailscaled_ready() {
  [ -S /var/run/tailscale/tailscaled.sock ] && tailscale debug prefs >/dev/null 2>&1
}

start_tailscaled() {
  if tailscaled_ready; then
    return 0
  fi
  mkdir -p /var/run/tailscale /var/lib/tailscale
  local tun_arg=()
  if [ ! -c /dev/net/tun ]; then
    tun_arg=(--tun=userspace-networking)
    log "No /dev/net/tun; using userspace networking"
  fi
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && [ ${#tun_arg[@]} -eq 0 ]; then
    systemctl enable --now tailscaled
    for _ in $(seq 1 30); do
      tailscaled_ready && return 0
      sleep 1
    done
    log "ERROR: tailscaled failed to become ready"
    exit 1
  fi
  log "Starting tailscaled without systemd"
  pkill -x tailscaled 2>/dev/null || true
  tailscaled "${tun_arg[@]}" \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    >/var/log/tailscaled.log 2>&1 &
  for _ in $(seq 1 30); do
    tailscaled_ready && return 0
    sleep 1
  done
  log "ERROR: tailscaled failed to start"
  tail -20 /var/log/tailscaled.log || true
  exit 1
}

require_root "$@"

if ! command -v tailscale >/dev/null 2>&1; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

start_tailscaled

HOSTNAME="${TAILSCALE_HOSTNAME:-$(hostname -s)}"
AUTH_KEY="$(resolve_auth_key)"

if [ -z "$AUTH_KEY" ]; then
  log "ERROR: no Tailscale auth key (set TAILSCALE_AUTHKEY or a Cursor secret named like 'Tailscale Auth key')"
  exit 1
fi

if tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
  log "Tailscale already connected"
elif tailscale status 2>/dev/null | grep -q '^100\.'; then
  log "Tailscale already connected"
else
  log "Joining tailnet as ${HOSTNAME}"
  tailscale up --auth-key="$AUTH_KEY" --hostname="$HOSTNAME" --accept-routes --ssh=false
fi

log "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo unknown)"
