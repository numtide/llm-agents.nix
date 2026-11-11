#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for agentsview package."""

import re
import sys
import urllib.error
from http import HTTPStatus
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"

RAW_BASE_URL = "https://raw.githubusercontent.com"
AGENTSVIEW_RAW_URL = f"{RAW_BASE_URL}/kenn-io/agentsview"

# The tagged tool pins the pricing snapshot on a separate artifact branch.
SNAPSHOT_TOOL_PATH = "internal/pricing/cmd/litellm-snapshot/main.go"

# Follow agentsview's sidecar pins rather than independent upstream releases.
SIDECAR_SCRIPT_PATH = "scripts/build-simple-fts.sh"
SIDECAR_REPOS = {"simple": "wangfenjin/simple", "cppjieba": "yanyiwu/cppjieba"}
SIDECAR_PIN_VARIABLES = {"simple": "simple_commit", "cppjieba": "cppjieba_commit"}
REVISION_RE = re.compile(r"[0-9a-f]{40}")
SHA256_SRI_RE = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")


class UnsupportedSidecarScriptError(ValueError):
    """The tagged sources no longer match the layout this updater understands."""


def _git_url(source: str) -> str:
    return f"https://github.com/{SIDECAR_REPOS[source]}.git"


def _single_assignment(script: str, name: str) -> str:
    """Read one literal top-level assignment without executing shell code."""
    assignment = re.compile(
        rf"^\s*(?:(?:export|readonly|local|declare(?:\s+-\w+)*)\s+)?{name}="
    )
    lines = [line for line in script.splitlines() if assignment.match(line)]
    if len(lines) != 1:
        msg = (
            f"expected one assignment to {name} in {SIDECAR_SCRIPT_PATH}, "
            f"found {len(lines)}"
        )
        raise UnsupportedSidecarScriptError(msg)
    match = re.fullmatch(rf'{name}="([^"$`\\]*)"', lines[0])
    if not match:
        msg = f"unsupported assignment in {SIDECAR_SCRIPT_PATH}: {lines[0]!r}"
        raise UnsupportedSidecarScriptError(msg)
    return match.group(1)


def parse_sidecar_pins(script: str) -> dict[str, str]:
    """Extract the simple and cppjieba revisions from build-simple-fts.sh."""
    repo = _single_assignment(script, "simple_repo")
    if repo != _git_url("simple"):
        msg = (
            f"{SIDECAR_SCRIPT_PATH} builds simple from {repo}, "
            f"expected {_git_url('simple')}"
        )
        raise UnsupportedSidecarScriptError(msg)

    pins = {}
    for key, variable in SIDECAR_PIN_VARIABLES.items():
        rev = _single_assignment(script, variable)
        if not REVISION_RE.fullmatch(rev):
            msg = (
                f"{variable} in {SIDECAR_SCRIPT_PATH} is not a full commit hash: "
                f"{rev!r}"
            )
            raise UnsupportedSidecarScriptError(msg)
        pins[key] = rev
    return pins


def check_cppjieba_repository(cmake: str) -> None:
    """Check cppjieba's repository, which is declared in simple's CMake file."""
    repos = re.findall(r"^\s*GIT_REPOSITORY\s+(\S+)\s*$", cmake, re.MULTILINE)
    if repos != [_git_url("cppjieba")]:
        msg = (
            f"simple's src/CMakeLists.txt fetches {repos}, "
            f"expected [{_git_url('cppjieba')!r}]"
        )
        raise UnsupportedSidecarScriptError(msg)


def _github_archive_hash(source: str, rev: str) -> str:
    # fetchFromGitHub with `rev` unpacks this exact archive.
    return calculate_url_hash(
        f"https://github.com/{SIDECAR_REPOS[source]}/archive/{rev}.tar.gz",
        unpack=True,
    )


def resolve_cjk(version: str) -> dict[str, dict[str, str]]:
    """Resolve the sidecar pins from the tagged agentsview source."""
    try:
        script = fetch_text(f"{AGENTSVIEW_RAW_URL}/v{version}/{SIDECAR_SCRIPT_PATH}")
    except urllib.error.HTTPError as e:
        e.close()
        if e.code != HTTPStatus.NOT_FOUND:
            raise
        msg = f"agentsview v{version} has no {SIDECAR_SCRIPT_PATH}"
        raise UnsupportedSidecarScriptError(msg) from e
    pins = parse_sidecar_pins(script)

    simple_cmake_url = (
        f"{RAW_BASE_URL}/{SIDECAR_REPOS['simple']}/{pins['simple']}/src/CMakeLists.txt"
    )
    check_cppjieba_repository(fetch_text(simple_cmake_url))

    print("Calculating CJK sidecar source hashes...")
    return {
        source: {"rev": rev, "hash": _github_archive_hash(source, rev)}
        for source, rev in pins.items()
    }


def check_cjk_metadata(cjk: object) -> None:
    """Fail on a hand-edited or truncated `cjk` entry instead of overwriting it."""
    if not isinstance(cjk, dict) or set(cjk) != set(SIDECAR_REPOS):
        msg = f"{HASHES_FILE}: cjk must have exactly {sorted(SIDECAR_REPOS)}"
        raise ValueError(msg)
    for source, entry in cjk.items():
        valid = (
            isinstance(entry, dict)
            and set(entry) == {"rev", "hash"}
            and isinstance(entry["rev"], str)
            and REVISION_RE.fullmatch(entry["rev"])
            and isinstance(entry["hash"], str)
            and SHA256_SRI_RE.fullmatch(entry["hash"])
        )
        if not valid:
            msg = (
                f"{HASHES_FILE}: cjk.{source} must be exactly a 40-hex `rev` "
                "and a sha256 SRI `hash`"
            )
            raise ValueError(msg)


def resolve_snapshot(version: str) -> dict[str, str]:
    """Derive the pinned LiteLLM snapshot URL/hash from the tagged source."""
    source = fetch_text(f"{AGENTSVIEW_RAW_URL}/v{version}/{SNAPSHOT_TOOL_PATH}")

    def const(name: str) -> str:
        match = re.search(rf'{name}\s*=\s*"([^"]+)"', source)
        if not match:
            msg = f"could not find {name} in {SNAPSHOT_TOOL_PATH}"
            raise ValueError(msg)
        return match.group(1)

    ref = const("defaultSnapshotRef")
    snapshot_file = const("defaultSnapshotFile")
    url = f"{AGENTSVIEW_RAW_URL}/{ref}/{snapshot_file}"

    print("Calculating LiteLLM snapshot hash...")
    return {"url": url, "hash": calculate_url_hash(url)}


def main() -> None:
    """Update the agentsview package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release("kenn-io", "agentsview")

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        if "cjk" in data:
            check_cjk_metadata(data["cjk"])
            print("Already up to date")
        else:
            # Bootstrap sidecar metadata without recalculating Go/npm hashes.
            data["cjk"] = resolve_cjk(current)
            save_hashes(HASHES_FILE, data)
            print(f"Added CJK sidecar pins for {current}")
        return

    # Reject unsupported releases before modifying hashes.json.
    cjk = resolve_cjk(latest)

    print("Calculating source hash...")
    url = f"https://github.com/kenn-io/agentsview/archive/refs/tags/v{latest}.tar.gz"
    source_hash = calculate_url_hash(url, unpack=True)

    data = {
        "version": latest,
        "hash": source_hash,
        "npmDepsHash": DUMMY_SHA256_HASH,
        "vendorHash": DUMMY_SHA256_HASH,
        "litellmSnapshot": resolve_snapshot(latest),
        "cjk": cjk,
    }

    original = HASHES_FILE.read_text()
    try:
        save_hashes(HASHES_FILE, data)
        update_dependency_hash(".#agentsview", "npmDepsHash", HASHES_FILE, data)
        update_dependency_hash(".#agentsview", "vendorHash", HASHES_FILE, data)
    except BaseException:
        # Dummy dependency hashes would leave the package unbuildable.
        HASHES_FILE.write_text(original)
        raise

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
