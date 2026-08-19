#!/usr/bin/env python3
"""Resolve a Tailscale auth key from env, injected cloud-agent secrets, or files.

Cursor Cloud can inject secrets under display names that are not valid
bash identifiers (for example ``Tailscale Auth key``). This helper reads
those names from CLOUD_AGENT_INJECTED_SECRET_NAMES / CLOUD_AGENT_ALL_SECRET_NAMES
and looks up the matching environment variable, including names with spaces.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

STANDARD_ENV_VARS = (
    "TAILSCALE_AUTHKEY",
    "TS_AUTHKEY",
    "TAILSCALE_AUTH_KEY",
)

SECRET_FILE_CANDIDATES = (
    Path("/run/secrets/tailscale-authkey"),
    Path("/etc/evergreen/tailscale-authkey"),
    Path.home() / ".config/evergreen/tailscale-authkey",
)


def _normalize_name(name: str) -> str:
    return " ".join(name.strip().lower().replace("-", " ").replace("_", " ").split())


def looks_like_tailscale_auth_name(name: str) -> bool:
    normalized = _normalize_name(name)
    if normalized in {
        "tailscale authkey",
        "ts authkey",
        "tailscale auth key",
        "tailscale api key",
    }:
        return True
    return "tailscale" in normalized and "key" in normalized


def injected_secret_names() -> list[str]:
    raw = os.environ.get("CLOUD_AGENT_INJECTED_SECRET_NAMES") or os.environ.get(
        "CLOUD_AGENT_ALL_SECRET_NAMES", ""
    )
    names: list[str] = []
    for part in raw.split(","):
        part = part.strip()
        if part:
            names.append(part)
    return names


def env_value(name: str) -> str:
    value = os.environ.get(name, "")
    if value.strip():
        return value.strip()
    stripped = name.strip()
    if stripped != name:
        value = os.environ.get(stripped, "")
        if value.strip():
            return value.strip()
    return ""


def read_secret_file(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def resolve_auth_key(script_dir: Path | None = None) -> str:
    for var in STANDARD_ENV_VARS:
        value = env_value(var)
        if value:
            return value

    for name in injected_secret_names():
        if looks_like_tailscale_auth_name(name):
            value = env_value(name)
            if value:
                return value

    for key, value in os.environ.items():
        if looks_like_tailscale_auth_name(key) and value.strip():
            return value.strip()

    candidates = list(SECRET_FILE_CANDIDATES)
    if script_dir is not None:
        candidates.append(script_dir / ".secrets" / "tailscale-authkey")
    for path in candidates:
        value = read_secret_file(path)
        if value:
            return value

    return ""


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    key = resolve_auth_key(script_dir)
    if not key:
        print(
            "ERROR: no Tailscale auth key found "
            "(set TAILSCALE_AUTHKEY / TAILSCALE_AUTH_KEY, a Cursor secret "
            "named like 'Tailscale Auth key', or bootstrap/.secrets/tailscale-authkey)",
            file=sys.stderr,
        )
        return 1
    sys.stdout.write(key)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
