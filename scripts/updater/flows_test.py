"""Behavioural tests for the flows that have offline-testable logic.

fetch_json is patched so the manifest-checksums flow runs offline.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

from updater import http
from updater.fetch import Resolved
from updater.flows import github_source as gs
from updater.flows import manifest_checksums as mc
from updater.flows.bun_github import update_bun_github
from updater.hash import hex_to_sri
from updater.nix import NixCommandError

_MANIFEST = {
    "platforms": {
        "linux-x64": {"checksum": "00" * 32},
        "linux-arm64": {"checksum": "11" * 32},
        "darwin-arm64": {"checksum": "22" * 32},
    }
}
_PLATFORMS = {
    "x86_64-linux": "linux-x64",
    "aarch64-linux": "linux-arm64",
    "aarch64-darwin": "darwin-arm64",
}


class TestManifestChecksums(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.pkg = Path(self._dir.name)
        (self.pkg / "hashes.json").write_text(
            json.dumps({"version": "1.0.0", "hashes": {}})
        )
        self._orig = http.fetch_json

        def fake(_url: str) -> dict[str, Any]:
            return _MANIFEST

        http.fetch_json = fake  # type: ignore[assignment]

    def tearDown(self) -> None:
        http.fetch_json = self._orig
        self._dir.cleanup()

    def _run(self, *, latest: str, allow_downgrade: bool) -> dict[str, Any]:
        mc.update_manifest_checksums(
            self.pkg,
            fetch_latest=lambda: latest,
            manifest_url_template="https://h/{version}/manifest.json",
            checksum_path="platforms.{platform}.checksum",
            platforms=_PLATFORMS,
            allow_downgrade=allow_downgrade,
        )
        loaded: dict[str, Any] = json.loads((self.pkg / "hashes.json").read_text())
        return loaded

    def test_extracts_and_converts_to_sri(self) -> None:
        data = self._run(latest="2.0.0", allow_downgrade=False)
        self.assertEqual(data["version"], "2.0.0")
        self.assertEqual(data["hashes"]["x86_64-linux"], hex_to_sri("00" * 32))
        self.assertEqual(data["hashes"]["aarch64-darwin"], hex_to_sri("22" * 32))

    def test_follow_pointer_allows_downgrade(self) -> None:
        # 1.0.0 -> 0.9.0 writes because allow_downgrade is set.
        data = self._run(latest="0.9.0", allow_downgrade=True)
        self.assertEqual(data["version"], "0.9.0")

    def test_semver_skips_downgrade(self) -> None:
        data = self._run(latest="0.9.0", allow_downgrade=False)
        self.assertEqual(data["version"], "1.0.0")  # unchanged


class TestBunGithub(unittest.TestCase):
    def test_dep_hash_without_flake_attr_fails_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pkg = Path(tmp)
            hashes = pkg / "hashes.json"
            hashes.write_text('{"version": "1.0.0", "hash": "sha256-x"}\n')
            with self.assertRaises(ValueError):
                update_bun_github(pkg, "o", "r", dep_hash_key="cargoHash")
            self.assertEqual(
                json.loads(hashes.read_text()), {"version": "1.0.0", "hash": "sha256-x"}
            )


class TestGithubSource(unittest.TestCase):
    def test_dependency_failure_restores_pins_and_retry_finishes(self) -> None:
        release = Resolved(version="2.0.0", ref="rea-agents-2.0.0")
        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch("updater.fetch.PurlFetcher.default") as fetcher,
            mock.patch("updater.nix.nix_command") as build,
        ):
            pkg = Path(tmp)
            hashes = pkg / "hashes.json"
            original = b'{"version":"1.0.0","hash":"old","npmDepsHash":"old-deps"}\n'
            hashes.write_bytes(original)
            fetcher.return_value.hashes.return_value = {"src": "new-src"}
            build.side_effect = [
                NixCommandError("builder unavailable"),
                NixCommandError("hash mismatch; got: sha256-YWJj"),
            ]
            args = (pkg, "morluto", "rea", ".#rea", "npmDepsHash")
            with self.assertRaises(SystemExit):
                gs.update_github_source(*args, release=release)
            self.assertEqual(hashes.read_bytes(), original)
            gs.update_github_source(*args, release=release)
            self.assertEqual(
                json.loads(hashes.read_text()),
                {"version": "2.0.0", "hash": "new-src", "npmDepsHash": "sha256-YWJj"},
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
