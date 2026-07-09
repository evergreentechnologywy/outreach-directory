#!/usr/bin/env bash
# Cursor Cloud: join tailnet using injected TAILSCALE_AUTH_KEY runtime secret.
set -euo pipefail

log() { printf '[install_cursor_cloud_tailscale] %s\n' "$*"; }

if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
  log "ERROR: TAILSCALE_AUTH_KEY runtime secret is not set"
  exit 1
fi

export TAILSCALE_AUTHKEY="${TAILSCALE_AUTH_KEY}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/start_tailscale_cloud.sh" "$@"
