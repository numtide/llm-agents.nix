"""Tests for the declarative updater runner (config -> flow dispatch).

Flows are replaced with recorders, so run() is checked for correct dispatch.
"""

from __future__ import annotations

import unittest
from pathlib import Path
from typing import Any

from updater import http
from updater.run import _latest_git_tag, _version_getter, run

PKG = Path("packages/example")


class Recorder:
    """A stand-in flow that records the call it received."""

    def __init__(self) -> None:
        self.args: tuple[Any, ...] | None = None
        self.kwargs: dict[str, Any] | None = None

    def __call__(self, *args: Any, **kwargs: Any) -> None:
        self.args = args
        self.kwargs = kwargs


def recorders() -> dict[str, Recorder]:
    kinds = (
        "github-source",
        "npm",
        "bun-github",
        "platform",
        "manifest",
        "manifest-checksums",
    )
    return {k: Recorder() for k in kinds}


class TestRun(unittest.TestCase):
    def test_github_source(self) -> None:
        flows = recorders()
        run(
            PKG,
            {
                "kind": "github-source",
                "purl": "pkg:github/charmbracelet/crush",
                "flakeAttr": ".#crush",
                "depHashKey": "vendorHash",
            },
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["github-source"]
        self.assertEqual(
            rec.args, (PKG, "charmbracelet", "crush", ".#crush", "vendorHash")
        )

    def test_bun_github_default_prefix(self) -> None:
        flows = recorders()
        run(
            PKG,
            {"kind": "bun-github", "purl": "pkg:github/gmickel/gno"},
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["bun-github"]
        self.assertEqual(rec.args, (PKG, "gmickel", "gno"))
        self.assertEqual(rec.kwargs, {"ref_prefix": "v"})

    def test_bun_github_custom_prefix(self) -> None:
        flows = recorders()
        run(
            PKG,
            {"kind": "bun-github", "purl": "pkg:github/o/r", "refPrefix": "release-"},
            flows=flows,  # type: ignore[arg-type]
        )
        self.assertEqual(flows["bun-github"].kwargs, {"ref_prefix": "release-"})

    def test_npm_scoped(self) -> None:
        flows = recorders()
        run(
            PKG,
            {
                "kind": "npm",
                "purl": "pkg:npm/%40zaly/cli",
                "flakeAttr": ".#zaly",
                "fetchzip": True,
            },
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["npm"]
        assert rec.args is not None
        self.assertEqual(rec.args[:3], (PKG, "@zaly/cli", ".#zaly"))
        assert rec.kwargs is not None
        self.assertTrue(rec.kwargs["fetchzip"])
        self.assertTrue(rec.kwargs["require_lockfile"])

    def test_npm_unscoped(self) -> None:
        flows = recorders()
        run(
            PKG,
            {"kind": "npm", "purl": "pkg:npm/skills", "flakeAttr": ".#skills"},
            flows=flows,  # type: ignore[arg-type]
        )
        assert flows["npm"].args is not None
        self.assertEqual(flows["npm"].args[1], "skills")

    def test_npm_dist_tag(self) -> None:
        flows = recorders()
        run(
            PKG,
            {
                "kind": "npm",
                "purl": "pkg:npm/omo-ai?x_dist_tag=beta",
                "flakeAttr": ".#omo-ai",
            },
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["npm"]
        assert rec.args is not None
        self.assertEqual(rec.args[1], "omo-ai")
        assert rec.kwargs is not None
        self.assertEqual(rec.kwargs["dist_tag"], "beta")

    def test_platform_github_source(self) -> None:
        flows = recorders()
        run(
            PKG,
            {
                "kind": "platform",
                "versionSource": {
                    "type": "github",
                    "owner": "anomalyco",
                    "repo": "opencode",
                },
                "urlTemplate": "https://x/{version}/{platform}",
                "platforms": {"x86_64-linux": "linux-x64.tar.gz"},
            },
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["platform"]
        assert rec.kwargs is not None
        self.assertEqual(rec.kwargs["url_template"], "https://x/{version}/{platform}")
        self.assertEqual(rec.kwargs["platforms"], {"x86_64-linux": "linux-x64.tar.gz"})
        self.assertTrue(callable(rec.kwargs["fetch_latest"]))

    def test_platform_version_sources(self) -> None:
        # Each type builds a callable without raising.
        for source in (
            {"type": "github", "owner": "o", "repo": "r"},
            {"type": "npm", "package": "@x/y", "tag": "next"},
            {"type": "text", "url": "https://x/v", "regex": r"v(\d+)"},
            {"type": "text", "url": "https://x/v"},  # no regex -> plain body
            {"type": "git-tags", "url": "https://gitea/api/.../tags"},
        ):
            self.assertTrue(callable(_version_getter(source)))
        with self.assertRaises(ValueError):
            _version_getter({"type": "bogus"})

    def test_git_tags_picks_highest_stripping_v(self) -> None:
        # Patch fetch_json; the getter imports it lazily from updater.http.
        def fake(_url: str) -> list[Any]:
            return [{"name": "v1.2.0"}, {"name": "v1.10.0"}, {"name": "v1.9.0"}]

        original = http.fetch_json
        http.fetch_json = fake  # type: ignore[assignment]
        try:
            self.assertEqual(_latest_git_tag("https://x/tags"), "1.10.0")
        finally:
            http.fetch_json = original

    def test_manifest(self) -> None:
        flows = recorders()
        run(
            PKG,
            {
                "kind": "manifest",
                "manifestUrl": "https://x/manifest.json",
                "platformMap": [
                    {"os": "linux", "arch": "amd64", "platform": "x86_64-linux"},
                    {"os": "darwin", "arch": "arm64", "platform": "aarch64-darwin"},
                ],
            },
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["manifest"]
        assert rec.kwargs is not None
        self.assertEqual(rec.kwargs["manifest_url"], "https://x/manifest.json")
        self.assertEqual(
            rec.kwargs["platform_map"],
            {("linux", "amd64"): "x86_64-linux", ("darwin", "arm64"): "aarch64-darwin"},
        )

    def test_manifest_checksums(self) -> None:
        flows = recorders()
        run(
            PKG,
            {
                "kind": "manifest-checksums",
                "versionSource": {"type": "text", "url": "https://x/latest"},
                "manifestUrl": "https://x/{version}/m.json",
                "checksumPath": "platforms.{platform}.checksum",
                "platforms": {"x86_64-linux": "linux-x64"},
                "versionPolicy": "follow_pointer",
            },
            flows=flows,  # type: ignore[arg-type]
        )
        rec = flows["manifest-checksums"]
        assert rec.kwargs is not None
        self.assertEqual(
            rec.kwargs["manifest_url_template"], "https://x/{version}/m.json"
        )
        self.assertEqual(rec.kwargs["checksum_path"], "platforms.{platform}.checksum")
        self.assertEqual(rec.kwargs["platforms"], {"x86_64-linux": "linux-x64"})
        self.assertTrue(rec.kwargs["allow_downgrade"])
        self.assertTrue(callable(rec.kwargs["fetch_latest"]))

    def test_unknown_kind_raises(self) -> None:
        with self.assertRaises(ValueError):
            run(PKG, {"kind": "mystery", "purl": "pkg:github/o/r"}, flows=recorders())  # type: ignore[arg-type]

    def test_github_source_needs_owner(self) -> None:
        with self.assertRaises(ValueError):
            run(
                PKG,
                {
                    "kind": "github-source",
                    "purl": "pkg:github/lonerepo",
                    "flakeAttr": ".#x",
                    "depHashKey": "vendorHash",
                },
                flows=recorders(),  # type: ignore[arg-type]
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
