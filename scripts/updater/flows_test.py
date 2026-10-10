"""Behavioural tests for the flows that have offline-testable logic.

fetch_json is patched so the manifest-checksums flow runs offline.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from updater import http
from updater.flows import manifest_checksums as mc
from updater.hash import hex_to_sri
from updater.run import run

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

    def test_json_feed_uses_one_stable_snapshot(self) -> None:
        requests: list[str] = []

        def fake(url: str) -> dict[str, Any]:
            requests.append(url)
            return {
                "version": "3.0.0",
                "stable": {
                    "linux": {
                        "version": "2.0.0",
                        "deb": {
                            "x64": {"sha256": "00" * 32},
                            "arm64": {"sha256": "11" * 32},
                        },
                    }
                },
            }

        http.fetch_json = fake  # type: ignore[assignment]
        url = "https://h/latest.json"
        run(
            self.pkg,
            {
                "kind": "manifest-checksums",
                "versionSource": {
                    "type": "json",
                    "url": url,
                    "path": "stable.linux.version",
                },
                "manifestUrl": url,
                "checksumPath": "stable.linux.deb.{platform}.sha256",
                "platforms": {"x86_64-linux": "x64", "aarch64-linux": "arm64"},
            },
        )
        data = json.loads((self.pkg / "hashes.json").read_text())
        self.assertEqual(requests, [url])
        self.assertEqual(data["version"], "2.0.0")
        self.assertEqual(
            data["hashes"],
            {
                "x86_64-linux": hex_to_sri("00" * 32),
                "aarch64-linux": hex_to_sri("11" * 32),
            },
        )

    def test_json_version_rejects_non_string_without_writing(self) -> None:
        original = (self.pkg / "hashes.json").read_text()

        def fake(_url: str) -> dict[str, Any]:
            return {"stable": {"version": 2}}

        http.fetch_json = fake  # type: ignore[assignment]
        with self.assertRaises(TypeError):
            mc.update_manifest_checksums(
                self.pkg,
                fetch_latest=lambda: "unused",
                manifest_url_template="https://h/latest.json",
                version_path="stable.version",
                checksum_path="platforms.{platform}.checksum",
                platforms=_PLATFORMS,
            )
        self.assertEqual((self.pkg / "hashes.json").read_text(), original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
