#!/usr/bin/env python3
"""Regression tests for REA release pinning."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import update
from updater.nix import NixCommandError


class TestReaUpdate(unittest.TestCase):
    def test_failed_dependency_hash_rolls_back_and_can_be_retried(self) -> None:
        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch.object(update, "PACKAGE_DIR", Path(tmp)),
            mock.patch.object(update, "calculate_url_hash", return_value="new-source"),
            mock.patch("updater.nix.nix_command") as build,
        ):
            path = Path(tmp) / "hashes.json"
            original = b'{"version":"1.0.0","hash":"source","npmDepsHash":"deps"}\n'
            path.write_bytes(original)
            build.side_effect = [
                NixCommandError("builder unavailable"),
                NixCommandError("hash mismatch; got: sha256-YWJj"),
            ]
            with self.assertRaises(SystemExit):
                update.update_release("rea-agents-2.0.0")
            self.assertEqual(path.read_bytes(), original)
            update.update_release("rea-agents-2.0.0")
            self.assertEqual(
                json.loads(path.read_text()),
                {
                    "version": "2.0.0",
                    "hash": "new-source",
                    "npmDepsHash": "sha256-YWJj",
                },
            )


if __name__ == "__main__":
    unittest.main()
