#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for the gomodel package.

gomodel is a Go binary with an embedded Svelte dashboard, so a release bump
changes three hashes: the GitHub source tarball, the Go module vendor hash and
the npm dependency hash for ``web/dashboard``. The declarative ``github-source``
updater only knows one dependency hash key, so this script recalculates the
other two itself.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"

OWNER = "ENTERPILOT"
REPO = "GoModel"


def main() -> None:
    """Update the gomodel package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print("Calculating source hash...")
    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    source_hash = calculate_url_hash(url, unpack=True)

    data = {
        "version": latest,
        "hash": source_hash,
        "vendorHash": DUMMY_SHA256_HASH,
        "npmDepsHash": DUMMY_SHA256_HASH,
    }

    original = HASHES_FILE.read_text()
    try:
        save_hashes(HASHES_FILE, data)
        update_dependency_hash(".#gomodel", "vendorHash", HASHES_FILE, data)
        update_dependency_hash(".#gomodel", "npmDepsHash", HASHES_FILE, data)
    except BaseException:
        # Dummy dependency hashes would leave the package unbuildable.
        HASHES_FILE.write_text(original)
        raise

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
