"""Tests for deciding whether a published npm-shrinkwrap.json is usable."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from updater.npm import _can_prefetch_npm_lockfile, _mispinned_bundled_deps


def _entry(name: str, version: str) -> dict[str, str]:
    return {
        "version": version,
        "resolved": f"https://registry.npmjs.org/{name}/-/{name}-{version}.tgz",
        "integrity": "sha512-aaaa",
    }


class TestCanPrefetchNpmLockfile(unittest.TestCase):
    def _check(self, packages: dict[str, Any]) -> bool:
        with tempfile.TemporaryDirectory() as tmpdir:
            lockfile = Path(tmpdir) / "npm-shrinkwrap.json"
            lockfile.write_text(json.dumps({"packages": packages}))
            return _can_prefetch_npm_lockfile(lockfile)

    def test_accepts_nested_dependencies(self) -> None:
        self.assertTrue(
            self._check(
                {
                    "": {"name": "@letta-ai/letta-code"},
                    "node_modules/ink": _entry("ink", "5.2.1"),
                    "node_modules/ink/node_modules/react": _entry("react", "18.3.1"),
                }
            )
        )

    def test_rejects_missing_integrity(self) -> None:
        entry = _entry("react", "18.2.0")
        del entry["integrity"]
        self.assertFalse(self._check({"": {}, "node_modules/react": entry}))

    def test_rejects_entries_below_a_missing_parent(self) -> None:
        # letta-code 0.34.11 cut its shrinkwrap out of a monorepo lockfile, so
        # its direct dependencies hang below a package that is not installed.
        self.assertFalse(
            self._check(
                {
                    "": {"name": "@letta-ai/letta-code"},
                    "node_modules/react": _entry("react", "18.3.1"),
                    "node_modules/@letta-ai/letta-code/node_modules/react": _entry(
                        "react", "18.2.0"
                    ),
                }
            )
        )


class TestMispinnedBundledDeps(unittest.TestCase):
    def test_finds_exact_pin_resolving_to_another_bundled_version(self) -> None:
        # paperclipai 2026.1117.0: the server bundles claude-agent-acp, which
        # pins an sdk version other than the one bundled next to it.
        server = "node_modules/server/node_modules"
        packages = {
            "": {},
            "node_modules/sdk": _entry("sdk", "1.0.0"),
            "node_modules/acp": {
                **_entry("acp", "2.0.0"),
                "dependencies": {"sdk": "1.0.0"},
            },
            f"{server}/sdk": {"version": "1.1.0", "inBundle": True},
            f"{server}/acp": {
                "version": "2.0.0",
                "inBundle": True,
                "dependencies": {"sdk": "1.0.0", "zod": "^4.0.0"},
            },
        }
        self.assertEqual(
            _mispinned_bundled_deps(packages), {f"{server}/acp": {"sdk": "1.0.0"}}
        )


if __name__ == "__main__":
    unittest.main()
