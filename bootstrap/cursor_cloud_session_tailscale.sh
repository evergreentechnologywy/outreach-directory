#!/usr/bin/env bash
# Cursor Cloud session fallback: ensure tailscaled is up and joined via TAILSCALE_AUTH_KEY.
set -euo pipefail

log() { printf '[cursor_cloud_session_tailscale] %s\n' "$*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
  fi
}

tailscaled_ready() {
  [ -S /var/run/tailscale/tailscaled.sock ] && tailscale debug prefs >/dev/null 2>&1
}

tailscale_connected() {
  tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"' \
    || tailscale ip -4 2>/dev/null | grep -q '^100\.'
}

require_root "$@"

if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
  log "ERROR: TAILSCALE_AUTH_KEY runtime secret is not set"
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscaled_ready; then
  mkdir -p /var/run/tailscale /var/lib/tailscale
  tun_args=()
  [ ! -c /dev/net/tun ] && tun_args=(--tun=userspace-networking)
  pkill -x tailscaled 2>/dev/null || true
  tailscaled "${tun_args[@]}" \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    >/var/log/tailscaled.log 2>&1 &
  for _ in $(seq 1 30); do tailscaled_ready && break; sleep 1; done
fi

if ! tailscale_connected; then
  hostname="${TAILSCALE_HOSTNAME:-$(hostname -s)}"
  log "Joining tailnet as ${hostname}"
  tailscale up --auth-key="${TAILSCALE_AUTH_KEY}" --hostname="${hostname}" --accept-routes --ssh=false
fi

log "Connected: $(tailscale ip -4 2>/dev/null || echo unknown)"
