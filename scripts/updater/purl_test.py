"""Golden tests for the purl parser.

GOLDEN is the real fixture set: every source identity from the in-repo updaters.
"""

from __future__ import annotations

import unittest
from dataclasses import FrozenInstanceError
from typing import Any

from updater.purl import Purl, PurlError

GOLDEN = [
    "pkg:generic/amp",
    "pkg:generic/antigravity-cli",
    "pkg:generic/claude-code",
    "pkg:generic/claude-desktop",
    "pkg:generic/coderabbit-cli",
    "pkg:generic/cubic",
    "pkg:generic/cursor-agent",
    "pkg:generic/droid",
    "pkg:generic/go",
    "pkg:generic/grok",
    "pkg:generic/jules",
    "pkg:generic/qoder-cli",
    "pkg:generic/qoder-cli-cn",
    "pkg:generic/swamp-club/swamp",
    "pkg:github/AltanS/collie",
    "pkg:github/Dicklesworthstone/beads_rust",
    "pkg:github/JetBrains/junie",
    "pkg:github/MrLesk/Backlog.md",
    "pkg:github/NousResearch/hermes-agent",
    "pkg:github/PrimeIntellect-ai/prime-agent",
    "pkg:github/XiaomiMiMo/MiMo-Code",
    "pkg:github/Yeachan-Heo/oh-my-codex",
    "pkg:github/aaif-goose/goose",
    "pkg:github/abhigyanpatwari/GitNexus",
    "pkg:github/alibaba/open-code-review",
    "pkg:github/anomalyco/opencode",
    "pkg:github/backnotprop/plannotator",
    "pkg:github/can1357/oh-my-pi",
    "pkg:github/ccusage/ccusage",
    "pkg:github/charmbracelet/crush",
    "pkg:github/cjpais/Handy",
    "pkg:github/code-yeongyu/oh-my-openagent",
    "pkg:github/editor-code-assistant/eca",
    "pkg:github/gmickel/gno",
    "pkg:github/gotalab/cc-sdd",
    "pkg:github/herdrdev/herdr",
    "pkg:github/iOfficeAI/AionUi",
    "pkg:github/kenn-io/agentsview",
    "pkg:github/modem-dev/hunk",
    "pkg:github/numtide/claudebox",
    "pkg:github/openai/codex",
    "pkg:github/parallel-web/parallel-web-tools",
    "pkg:github/router-for-me/CLIProxyAPI",
    "pkg:github/rtk-ai/icm",
    "pkg:github/slopus/happy",
    "pkg:github/subsy/ralph-tui",
    "pkg:github/tailcallhq/forgecode",
    "pkg:github/tobi/qmd",
    "pkg:github/yusukebe/ax",
    "pkg:npm/%40anthropic-ai/sandbox-runtime",
    "pkg:npm/%40earendil-works/pi-coding-agent",
    "pkg:npm/%40fission-ai/openspec",
    "pkg:npm/%40github/copilot",
    "pkg:npm/%40github/copilot-language-server",
    "pkg:npm/%40iflow-ai/iflow-cli",
    "pkg:npm/%40kilocode/cli",
    "pkg:npm/%40letta-ai/letta-code",
    "pkg:npm/%40opencode-ai/cli",
    "pkg:npm/%40zaly/cli",
    "pkg:npm/cline",
    "pkg:npm/openspecui",
    "pkg:npm/paperclipai",
    "pkg:npm/skills",
]


class TestGoldenSet(unittest.TestCase):
    def test_all_parse(self) -> None:
        for s in GOLDEN:
            with self.subTest(purl=s):
                p = Purl.parse(s)
                self.assertIn(p.type, {"github", "npm", "generic"})
                self.assertTrue(p.name, f"empty name for {s}")

    def test_reparse_equality(self) -> None:
        for s in GOLDEN:
            with self.subTest(purl=s):
                p = Purl.parse(s)
                self.assertEqual(Purl.parse(str(p)), p)

    def test_canonical_idempotent(self) -> None:
        for s in GOLDEN:
            with self.subTest(purl=s):
                once = str(Purl.parse(s))
                twice = str(Purl.parse(once))
                self.assertEqual(once, twice)


class TestComponents(unittest.TestCase):
    def test_scoped_npm(self) -> None:
        p = Purl.parse("pkg:npm/%40zaly/cli")
        self.assertEqual(p.type, "npm")
        self.assertEqual(p.namespace, "@zaly")  # %40 decoded
        self.assertEqual(p.name, "cli")
        self.assertIsNone(p.version)

    def test_unscoped_npm(self) -> None:
        p = Purl.parse("pkg:npm/skills")
        self.assertEqual((p.type, p.namespace, p.name), ("npm", None, "skills"))

    def test_github(self) -> None:
        p = Purl.parse("pkg:github/openai/codex")
        self.assertEqual((p.type, p.namespace, p.name), ("github", "openai", "codex"))

    def test_dotted_name_preserved(self) -> None:
        p = Purl.parse("pkg:github/MrLesk/Backlog.md")
        self.assertEqual(p.name, "Backlog.md")

    def test_generic_with_namespace(self) -> None:
        p = Purl.parse("pkg:generic/swamp-club/swamp")
        self.assertEqual((p.namespace, p.name), ("swamp-club", "swamp"))

    def test_type_lowercased(self) -> None:
        self.assertEqual(Purl.parse("pkg:GitHub/o/r").type, "github")


class TestFullForm(unittest.TestCase):
    RICH = "pkg:github/openai/codex@rust-v1.0.0?x_tag_template=rust-v%7Bv%7D&x_unpack=true#sub/dir"

    def test_version_and_qualifiers_and_subpath(self) -> None:
        p = Purl.parse(self.RICH)
        self.assertEqual(p.version, "rust-v1.0.0")
        self.assertEqual(p.q("x_tag_template"), "rust-v{v}")  # %7B..%7D decoded
        self.assertEqual(p.q("x_unpack"), "true")
        self.assertEqual(p.subpath, "sub/dir")

    def test_rich_round_trip(self) -> None:
        p = Purl.parse(self.RICH)
        self.assertEqual(Purl.parse(str(p)), p)

    def test_qualifier_default(self) -> None:
        p = Purl.parse("pkg:github/openai/codex")
        self.assertIsNone(p.q("x_tag_template"))
        self.assertEqual(p.q("x_tag_template", "v{v}"), "v{v}")

    def test_empty_qualifier_dropped(self) -> None:
        p = Purl.parse("pkg:npm/skills?x_foo=")
        self.assertNotIn("x_foo", p.qualifiers)

    def test_qualifiers_canonicalized_sorted(self) -> None:
        p = Purl.parse("pkg:npm/skills?b=2&a=1")
        self.assertEqual(str(p), "pkg:npm/skills?a=1&b=2")


class TestMutators(unittest.TestCase):
    def test_with_version(self) -> None:
        p = Purl.parse("pkg:github/openai/codex").with_version("1.2.3")
        self.assertEqual(p.version, "1.2.3")
        self.assertEqual(str(p), "pkg:github/openai/codex@1.2.3")

    def test_with_version_none_unpins(self) -> None:
        p = Purl.parse("pkg:github/openai/codex@1.2.3").with_version(None)
        self.assertIsNone(p.version)

    def test_with_qualifiers_merges(self) -> None:
        p = Purl.parse("pkg:github/openai/codex").with_qualifiers(x_tag_template="v{v}")
        self.assertEqual(p.q("x_tag_template"), "v{v}")

    def test_frozen(self) -> None:
        # Alias through Any so it is a runtime check, not a mypy read-only error.
        obj: Any = Purl.parse("pkg:npm/skills")
        with self.assertRaises(FrozenInstanceError):
            obj.name = "other"


class TestMalformed(unittest.TestCase):
    def test_rejects(self) -> None:
        for bad in [
            "",
            "   ",
            "npm/foo",
            "pkg:github",
            "pkg:npm/",
            "pkg:/name",
            "http://x",
        ]:
            with self.subTest(bad=bad), self.assertRaises(PurlError):
                Purl.parse(bad)


if __name__ == "__main__":
    unittest.main(verbosity=2)
