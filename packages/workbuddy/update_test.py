"""Regression tests for independent editions and failure-safe metadata updates."""

# ruff: noqa: INP001 -- tests for a standalone package updater

import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update as workbuddy

SOURCES = {
    "x86_64-linux": (
        "https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb",
        "https://download.codebuddy.cn/workbuddy/saas/linux-x64-deb/test.deb",
    ),
    "aarch64-linux": (
        "https://copilot.tencent.com/v2/update?platform=workbuddy-linux-arm64-deb",
        "https://download.codebuddy.cn/workbuddy/saas/linux-arm64-deb/test.deb",
    ),
    "aarch64-darwin": (
        "https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-arm64",
        "https://download.codebuddy.ai/workbuddy/saas/darwin-arm64/test.zip",
    ),
}


class UpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "hashes.json"
        self.data = {
            "version": "1.0.0",
            "versions": dict.fromkeys(SOURCES, "1.0.0"),
            "urls": {s: url for s, (_, url) in SOURCES.items()},
            "hashes": {s: f"recorded-{s}" for s in SOURCES},
        }
        self.path.write_text(json.dumps(self.data, indent=2) + "\n")
        self.original = self.path.read_bytes()
        self.releases = {
            api: {"version": "1.0.0", "url": url} for api, url in SOURCES.values()
        }
        self.enterContext(patch.object(workbuddy, "HASHES_FILE", self.path))
        self.fetch = self.enterContext(
            patch.object(workbuddy, "fetch_json", side_effect=self.releases.__getitem__)
        )
        self.hash = self.enterContext(
            patch.object(
                workbuddy, "calculate_url_hash", return_value="downloaded-hash"
            )
        )

    def test_unchanged_releases_use_correct_edition_without_rehashing(self) -> None:
        workbuddy.main()
        self.assertEqual(self.fetch.call_count, 3)
        self.assertEqual(
            {call.args[0] for call in self.fetch.call_args_list},
            {api for api, _ in SOURCES.values()},
        )
        self.hash.assert_not_called()
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_each_platform_can_update_independently(self) -> None:
        for system, (api, url) in SOURCES.items():
            with self.subTest(system=system):
                self.path.write_bytes(self.original)
                self.hash.reset_mock()
                self.releases[api]["version"] = "2.0.0"
                workbuddy.main()
                data = json.loads(self.path.read_text())
                expected = copy.deepcopy(self.data)
                expected["versions"][system] = "2.0.0"
                expected["hashes"][system] = "downloaded-hash"
                if system == "x86_64-linux":
                    expected["version"] = "2.0.0"
                self.assertEqual(data, expected)
                self.hash.assert_called_once_with(url)
                self.releases[api]["version"] = "1.0.0"

    def test_changed_url_with_same_version_is_rehashed(self) -> None:
        api, url = SOURCES["aarch64-darwin"]
        replacement = url.replace("test.zip", "repacked.zip")
        self.releases[api]["url"] = replacement
        workbuddy.main()
        self.hash.assert_called_once_with(replacement)
        self.assertEqual(
            json.loads(self.path.read_text())["urls"]["aarch64-darwin"], replacement
        )

    def test_force_refreshes_archives_republished_at_same_url(self) -> None:
        workbuddy.main(force=True)
        self.assertEqual(self.hash.call_count, 3)

    def test_initial_population_downloads_all_platforms(self) -> None:
        self.path.write_text("{}")
        workbuddy.main()
        self.assertEqual(self.hash.call_count, 3)
        self.assertEqual(set(json.loads(self.path.read_text())["hashes"]), set(SOURCES))

    def test_last_channel_failure_keeps_original_metadata(self) -> None:
        self.fetch.side_effect = [
            self.releases[SOURCES["x86_64-linux"][0]],
            self.releases[SOURCES["aarch64-linux"][0]],
            OSError("update API unavailable"),
        ]
        with self.assertRaisesRegex(OSError, "unavailable"):
            workbuddy.main(force=True)
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_hash_failure_keeps_original_metadata(self) -> None:
        self.hash.side_effect = ["new-linux-hash", OSError("download failed")]
        with self.assertRaisesRegex(OSError, "download failed"):
            workbuddy.main(force=True)
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_downgrade_on_any_channel_is_rejected(self) -> None:
        self.releases[SOURCES["aarch64-darwin"][0]]["version"] = "0.9.0"
        with self.assertRaisesRegex(RuntimeError, "refusing downgrade"):
            workbuddy.main()
        self.assertEqual(self.path.read_bytes(), self.original)

    def test_invalid_metadata_and_cross_edition_downloads_are_rejected(self) -> None:
        invalid_releases = [
            [],
            {},
            {"version": "", "url": SOURCES["aarch64-darwin"][1]},
            {"version": 123, "url": SOURCES["aarch64-darwin"][1]},
            {"version": "1.0.0", "url": None},
            {"version": "1.0.0", "url": SOURCES["x86_64-linux"][1]},
            {"version": "1.0.0", "url": "http://download.codebuddy.ai/test.zip"},
        ]
        for release in invalid_releases:
            with self.subTest(release=release):
                self.fetch.side_effect = None
                self.fetch.return_value = release
                with self.assertRaises((TypeError, ValueError)):
                    workbuddy.fetch_release("aarch64-darwin", "workbuddy-darwin-arm64")
                self.assertEqual(self.path.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
