"""Update the sub2api source and dependency hashes."""

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
OWNER = "Wei-Shaw"
REPO = "sub2api"


def main() -> None:
    """Update the sub2api hashes.json file."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    source_url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    new_data = {
        "version": latest,
        "hash": calculate_url_hash(source_url, unpack=True),
        "pnpmDepsHash": DUMMY_SHA256_HASH,
        "vendorHash": DUMMY_SHA256_HASH,
    }
    save_hashes(HASHES_FILE, new_data)

    # Build the frontend dependency FOD first so the backend build can reuse it
    # when calculating vendorHash.
    update_dependency_hash(
        ".#sub2api.frontend.pnpmDeps",
        "pnpmDepsHash",
        HASHES_FILE,
        new_data,
    )
    update_dependency_hash(".#sub2api", "vendorHash", HASHES_FILE, new_data)

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
