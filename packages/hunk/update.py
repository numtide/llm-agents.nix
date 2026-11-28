"""Update script for hunk package.

Custom updater needed because hunk uses bun2nix: after each version
bump the bun.nix lockfile must be regenerated from the upstream
bun.lock using the bun2nix CLI.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    clone_and_generate_bun_nix,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
)

PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent
HASHES_FILE = PKG_DIR / "hashes.json"
BUN_NIX = PKG_DIR / "bun.nix"

OWNER = "modem-dev"
REPO = "hunk"


def main() -> None:
    """Update the hunk package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating hunk from {current} to {latest}")

    print("Calculating source hash...")
    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    source_hash = calculate_url_hash(url, unpack=True)

    save_hashes(HASHES_FILE, {"version": latest, "hash": source_hash})
    print("Updated hashes.json")

    clone_and_generate_bun_nix(
        OWNER,
        REPO,
        latest,
        BUN_NIX,
        FLAKE_ROOT,
        pkg_dir=PKG_DIR,
        ref_prefix="v",
    )

    print(f"Updated hunk to {latest}")


if __name__ == "__main__":
    main()
