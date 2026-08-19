#!/usr/bin/env python3
"""Unit tests for Tailscale auth-key resolution, including spaced Cursor secret names."""

from __future__ import annotations

import os
import unittest
from pathlib import Path
from unittest.mock import patch

from resolve_tailscale_auth_key import looks_like_tailscale_auth_name, resolve_auth_key


class ResolveTailscaleAuthKeyTest(unittest.TestCase):
    def test_spaced_display_name_is_recognized(self) -> None:
        self.assertTrue(looks_like_tailscale_auth_name("Tailscale Auth key"))
        self.assertTrue(looks_like_tailscale_auth_name(" TAILSCALE_AUTH_KEY "))
        self.assertFalse(looks_like_tailscale_auth_name("RESEND_API_KEY"))

    def test_resolves_spaced_injected_secret(self) -> None:
        env = {
            "CLOUD_AGENT_INJECTED_SECRET_NAMES": " Tailscale Auth key",
            "Tailscale Auth key": "tskey-auth-unit-test-example",
        }
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(resolve_auth_key(), "tskey-auth-unit-test-example")

    def test_prefers_canonical_env_var(self) -> None:
        env = {
            "TAILSCALE_AUTHKEY": "tskey-auth-canonical",
            "CLOUD_AGENT_INJECTED_SECRET_NAMES": "Tailscale Auth key",
            "Tailscale Auth key": "tskey-auth-spaced",
        }
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(resolve_auth_key(), "tskey-auth-canonical")

    def test_reads_secret_file(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            script_dir = Path("/tmp/does-not-exist-resolve-ts")
            self.assertEqual(resolve_auth_key(script_dir), "")


if __name__ == "__main__":
    unittest.main()
