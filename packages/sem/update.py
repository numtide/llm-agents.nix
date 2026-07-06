#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for sem package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"

OWNER = "Ataraxy-Labs"
REPO = "sem"


def main() -> None:
    """Update the sem package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating sem from {current} to {latest}")

    print("Calculating source hash...")
    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    source_hash = calculate_url_hash(url, unpack=True)
    print(f"  source hash: {source_hash}")

    data = {
        "version": latest,
        "hash": source_hash,
        "cargoHash": DUMMY_SHA256_HASH,
    }
    save_hashes(HASHES_FILE, data)

    data["cargoHash"] = calculate_dependency_hash(
        package_attr=".#sem",
        hash_key="cargoHash",
        hashes_file=HASHES_FILE,
        data=data,
    )
    save_hashes(HASHES_FILE, data)
    print(f"  cargoHash: {data['cargoHash']}")

    print(f"Updated sem to {latest}")


if __name__ == "__main__":
    main()
