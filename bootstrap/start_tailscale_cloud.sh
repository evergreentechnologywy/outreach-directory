#!/usr/bin/env bash
# Evergreen fleet: install Tailscale and join tailnet on cloud agents.
set -euo pipefail

log() { printf '[start_tailscale_cloud] %s\n' "$*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
  fi
}

resolve_auth_key() {
  local key=""
  for var in TAILSCALE_AUTHKEY TS_AUTHKEY TAILSCALE_AUTH_KEY; do
    if [ -n "${!var:-}" ]; then
      key="${!var}"
      break
    fi
  done
  if [ -z "$key" ]; then
    for path in \
      /run/secrets/tailscale-authkey \
      /etc/evergreen/tailscale-authkey \
      "${HOME}/.config/evergreen/tailscale-authkey" \
      "$(dirname "$0")/.secrets/tailscale-authkey"; do
      if [ -f "$path" ]; then
        key="$(tr -d '[:space:]' <"$path")"
        break
      fi
    done
  fi
  if [ -z "$key" ] && [ -n "${CLOUD_AGENT_INJECTED_SECRET_NAMES:-}" ]; then
    IFS=',' read -ra _names <<<"$CLOUD_AGENT_INJECTED_SECRET_NAMES"
    for name in "${_names[@]}"; do
      case "$name" in
        TAILSCALE_AUTHKEY|TS_AUTHKEY|TAILSCALE_AUTH_KEY)
          key="${!name:-}"
          [ -n "$key" ] && break
          ;;
      esac
    done
  fi
  printf '%s' "$key"
}

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
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl enable --now tailscaled
    return 0
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

if tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
  log "Tailscale already connected"
elif tailscale status 2>/dev/null | grep -q '^100\.'; then
  log "Tailscale already connected"
else
  if [ -z "$AUTH_KEY" ]; then
    log "ERROR: no Tailscale auth key (set TAILSCALE_AUTHKEY or bootstrap/.secrets/tailscale-authkey)"
    exit 1
  fi
  log "Joining tailnet as ${HOSTNAME}"
  tailscale up --auth-key="$AUTH_KEY" --hostname="$HOSTNAME" --accept-routes --ssh=false
fi

log "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo unknown)"
