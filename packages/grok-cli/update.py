#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for grok-cli package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"

PLATFORMS = {
    "x86_64-linux": "linux-x86_64",
    "aarch64-linux": "linux-aarch64",
    "aarch64-darwin": "macos-aarch64",
}

VERSION_URL = "https://storage.googleapis.com/grok-build-public-artifacts/cli/stable"


def main() -> None:
    """Update grok-cli hashes."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_text(VERSION_URL).strip()

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    url_template = f"https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-{latest}-{{platform}}"
    hashes = calculate_platform_hashes(url_template, PLATFORMS)

    save_hashes(HASHES_FILE, {"version": latest, "hashes": hashes})
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
