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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve before sudo: Cursor injects display names with spaces that sudo may drop.
AUTH_KEY="$(python3 "${SCRIPT_DIR}/resolve_tailscale_auth_key.py")"
export TAILSCALE_AUTHKEY="${AUTH_KEY}"
export TAILSCALE_AUTH_KEY="${AUTH_KEY}"

require_root "$@"

if ! command -v tailscale >/dev/null 2>&1 || ! command -v tailscaled >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh || true
fi
if ! command -v tailscale >/dev/null 2>&1 || ! command -v tailscaled >/dev/null 2>&1; then
  log "Official installer unavailable; using static binaries"
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) log "ERROR: unsupported architecture $(uname -m)"; exit 1 ;;
  esac
  tmp="$(mktemp -d)"
  curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_latest_${arch}.tgz" | tar -xz -C "$tmp"
  install -m 0755 "$tmp"/tailscale_*/tailscale /usr/bin/tailscale
  install -m 0755 "$tmp"/tailscale_*/tailscaled /usr/bin/tailscaled
  rm -rf "$tmp"
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
  if ! tailscaled_ready; then
    log "ERROR: tailscaled failed to start"
    tail -20 /var/log/tailscaled.log || true
    exit 1
  fi
fi

if ! tailscale_connected; then
  hostname="${TAILSCALE_HOSTNAME:-$(hostname -s)}"
  log "Joining tailnet as ${hostname}"
  tailscale up --auth-key="${AUTH_KEY}" --hostname="${hostname}" --accept-routes --ssh=false
fi

log "Connected: $(tailscale ip -4 2>/dev/null || echo unknown)"
