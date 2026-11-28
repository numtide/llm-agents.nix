"""Update script for oh-my-opencode package.

Custom updater needed because oh-my-opencode uses bun2nix (bun.nix must be
regenerated from upstream bun.lock) and fetches submodules, so the source
hash is recovered from a failed build via update_dependency_hash
instead of nix-prefetch-url.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    clone_and_generate_bun_nix,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)

PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent
HASHES_FILE = PKG_DIR / "hashes.json"
BUN_NIX = PKG_DIR / "bun.nix"

OWNER = "code-yeongyu"
REPO = "oh-my-openagent"


def main() -> None:
    """Update the oh-my-opencode package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating oh-my-opencode from {current} to {latest}")

    # Step 1: Bump version; hashes are filled in by the steps below
    data["version"] = latest
    save_hashes(HASHES_FILE, data)

    # Step 2: Regenerate bun.nix from upstream bun.lock
    clone_and_generate_bun_nix(
        OWNER,
        REPO,
        latest,
        BUN_NIX,
        FLAKE_ROOT,
        ref_prefix="v",
        pkg_dir=PKG_DIR,
    )

    # Step 3: Source hash. nix-prefetch-url can't be used because the
    # GitHub tarball excludes submodule contents.
    print("Calculating source hash (with submodules)...")
    update_dependency_hash(".#oh-my-opencode", "hash", HASHES_FILE, data)

    print(f"Updated oh-my-opencode to {latest}")


if __name__ == "__main__":
    main()
