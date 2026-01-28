#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for claudebox package.

This script:
1. Fetches the latest release from numtide/claudebox
2. Downloads package.nix from upstream
3. Updates source.nix with the new version and hash
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_text,
    should_update,
)

PACKAGE_DIR = Path(__file__).parent
SOURCE_NIX = PACKAGE_DIR / "source.nix"
PACKAGE_NIX = PACKAGE_DIR / "package.nix"

OWNER = "numtide"
REPO = "claudebox"


def get_current_version() -> str:
    """Extract current version from source.nix."""
    content = SOURCE_NIX.read_text()
    match = re.search(r'rev\s*=\s*"v([^"]+)"', content)
    if not match:
        msg = "Could not find version in source.nix"
        raise ValueError(msg)
    return match.group(1)


def update_source_nix(version: str, hash_value: str) -> None:
    """Update version and hash in source.nix."""
    content = SOURCE_NIX.read_text()

    # Update rev
    content = re.sub(
        r'(rev\s*=\s*)"[^"]+"',
        f'\\1"v{version}"',
        content,
    )

    # Update hash
    content = re.sub(
        r'(hash\s*=\s*)"[^"]+"',
        f'\\1"{hash_value}"',
        content,
    )

    SOURCE_NIX.write_text(content)


def fetch_upstream_package_nix(version: str) -> str:
    """Fetch package.nix from upstream at the given version."""
    url = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/v{version}/package.nix"
    return fetch_text(url)


def main() -> None:
    """Update the claudebox package."""
    current = get_current_version()
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    # Fetch upstream package.nix
    print("Fetching upstream package.nix...")
    upstream_package_nix = fetch_upstream_package_nix(latest)
    PACKAGE_NIX.write_text(upstream_package_nix)
    print("Updated package.nix from upstream")

    # Calculate source hash
    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    print("Calculating source hash...")
    source_hash = calculate_url_hash(url, unpack=True)

    # Update source.nix
    update_source_nix(latest, source_hash)
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
