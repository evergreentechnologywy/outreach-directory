#!/usr/bin/env bash
# Cursor Cloud: join tailnet using the injected Tailscale auth secret.
# Accepts TAILSCALE_AUTH_KEY / TAILSCALE_AUTHKEY and Cursor display names
# such as "Tailscale Auth key".
set -euo pipefail

log() { printf '[install_cursor_cloud_tailscale] %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTH_KEY="$(python3 "${SCRIPT_DIR}/resolve_tailscale_auth_key.py")"
export TAILSCALE_AUTHKEY="${AUTH_KEY}"
export TAILSCALE_AUTH_KEY="${AUTH_KEY}"
exec bash "${SCRIPT_DIR}/start_tailscale_cloud.sh" "$@"
