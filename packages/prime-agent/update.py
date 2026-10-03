#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update Prime Agent to the latest commit on upstream main."""

from __future__ import annotations

import re
import sys
import tomllib
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import calculate_url_hash, fetch_json, fetch_text
from updater.hash import DUMMY_SHA256_HASH, extract_hash_from_build_error
from updater.nix import NixCommandError, nix_build

OWNER = "PrimeIntellect-ai"
REPO = "prime-agent"
PACKAGE_ATTR = ".#packages.x86_64-linux.prime-agent"
PACKAGE_NIX = Path(__file__).parent / "package.nix"


def replace_once(text: str, pattern: str, replacement: str) -> str:
    """Replace exactly one package field."""
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        msg = f"Expected one match for {pattern!r}, found {count}"
        raise ValueError(msg)
    return updated


def main_commit() -> tuple[str, str]:
    """Return latest main commit SHA and UTC commit date."""
    data = fetch_json(f"https://api.github.com/repos/{OWNER}/{REPO}/commits/main")
    if not isinstance(data, dict) or not isinstance(data.get("sha"), str):
        msg = "GitHub main response has no commit SHA"
        raise TypeError(msg)
    commit = data.get("commit")
    committer = commit.get("committer") if isinstance(commit, dict) else None
    timestamp = committer.get("date") if isinstance(committer, dict) else None
    if not isinstance(timestamp, str):
        msg = "GitHub main response has no committer date"
        raise TypeError(msg)
    date = datetime.fromisoformat(timestamp).date().isoformat()
    return data["sha"], date


def workspace_version(rev: str) -> str:
    """Read upstream workspace version at one immutable revision."""
    url = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{rev}/Cargo.toml"
    data = tomllib.loads(fetch_text(url))
    workspace = data.get("workspace")
    package = workspace.get("package") if isinstance(workspace, dict) else None
    version = package.get("version") if isinstance(package, dict) else None
    if not isinstance(version, str):
        msg = "Upstream Cargo.toml has no workspace.package.version"
        raise TypeError(msg)
    return version


def main() -> None:
    """Pin main, recalculate fixed-output hashes, and validate on Linux."""
    original = PACKAGE_NIX.read_text()
    latest_rev, date = main_commit()
    current_match = re.search(r'^    rev = "([0-9a-f]{40})";', original, re.MULTILINE)
    if current_match is None:
        msg = "package.nix has no pinned source revision"
        raise ValueError(msg)

    print(f"Current: {current_match.group(1)}, Latest: {latest_rev}")
    if current_match.group(1) == latest_rev:
        print("Already up to date")
        return

    version = f"{workspace_version(latest_rev)}-unstable-{date}"
    source_url = f"https://github.com/{OWNER}/{REPO}/archive/{latest_rev}.tar.gz"
    print("Calculating source hash...")
    source_hash = calculate_url_hash(source_url, unpack=True)

    try:
        updated = replace_once(
            original,
            r'^(  version = ")[^"]+(";)$',
            rf"\g<1>{version}\g<2>",
        )
        updated = replace_once(
            updated,
            r'^(    rev = ")[0-9a-f]{40}(";)$',
            rf"\g<1>{latest_rev}\g<2>",
        )
        updated = replace_once(
            updated,
            r'^(    hash = ")[^"]+(";)$',
            rf"\g<1>{source_hash}\g<2>",
        )
        updated = replace_once(
            updated,
            r'^(  cargoHash = ")[^"]+(";)$',
            rf"\g<1>{DUMMY_SHA256_HASH}\g<2>",
        )
        PACKAGE_NIX.write_text(updated)

        print("Calculating cargoHash...")
        try:
            nix_build(PACKAGE_ATTR)
        except NixCommandError as error:
            cargo_hash = extract_hash_from_build_error(str(error))
            if cargo_hash is None:
                msg = "Could not extract cargoHash from Nix build"
                raise ValueError(msg) from error
        else:
            msg = "Build unexpectedly accepted dummy cargoHash"
            raise ValueError(msg)

        PACKAGE_NIX.write_text(
            replace_once(
                PACKAGE_NIX.read_text(),
                r'^(  cargoHash = ")[^"]+(";)$',
                rf"\g<1>{cargo_hash}\g<2>",
            )
        )

        print("Validating updated package on x86_64-linux...")
        nix_build(PACKAGE_ATTR)
        print(f"Updated to {version} ({latest_rev})")
    except Exception:
        PACKAGE_NIX.write_text(original)
        raise


if __name__ == "__main__":
    main()
