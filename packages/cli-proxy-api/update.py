#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for cli-proxy-api package."""

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

PLATFORMS = {
    "x86_64-linux": "linux_amd64",
    "aarch64-linux": "linux_arm64",
    "x86_64-darwin": "darwin_amd64",
    "aarch64-darwin": "darwin_arm64",
}


def main() -> None:
    """Update the cli-proxy-api package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release("router-for-me", "CLIProxyAPI")

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    url_template = f"https://github.com/router-for-me/CLIProxyAPI/releases/download/v{latest}/CLIProxyAPI_{latest}_{{platform}}.tar.gz"
    hashes = calculate_platform_hashes(url_template, PLATFORMS)

    save_hashes(HASHES_FILE, {"version": latest, "hashes": hashes})
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
