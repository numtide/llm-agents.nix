#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for bun-bin package.

Fetches the latest stable Bun release from GitHub and updates hashes.json.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"

# Maps nix platform to bun archive name component
PLATFORMS = {
    "aarch64-darwin": "darwin-aarch64",
    "aarch64-linux": "linux-aarch64",
    "x86_64-darwin": "darwin-x64-baseline",
    "x86_64-linux": "linux-x64",
}

URL_TEMPLATE = (
    "https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{platform}.zip"
)


def main() -> None:
    """Update the bun-bin package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]

    print(f"Current: {current}")

    latest = fetch_github_latest_release("oven-sh", "bun")
    # Bun tags are "bun-v1.2.3"
    latest = latest.removeprefix("bun-v")
    print(f"Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    hashes = calculate_platform_hashes(URL_TEMPLATE, PLATFORMS, version=latest)
    for plat, h in sorted(hashes.items()):
        print(f"  {plat}: {h}")

    save_hashes(HASHES_FILE, {"version": latest, "hashes": hashes})
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
