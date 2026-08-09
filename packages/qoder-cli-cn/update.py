#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for qoder-cli package.

Fetches version and hashes directly from the official manifest.
"""

import base64
import binascii
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    fetch_json,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"
MANIFEST_URL = (
    "https://static.qoder.com.cn/qoder-cli-cn/channels/manifest.json"
)

# Map manifest os/arch to Nix platform names
PLATFORM_MAP = {
    ("linux", "amd64"): "x86_64-linux",
    ("linux", "arm64"): "aarch64-linux",
    ("darwin", "arm64"): "aarch64-darwin",
}


def hex_to_sri(hex_hash: str) -> str:
    """Convert hex SHA256 hash to SRI format (sha256-base64)."""
    raw_bytes = binascii.unhexlify(hex_hash)
    b64 = base64.b64encode(raw_bytes).decode("ascii")
    return f"sha256-{b64}"


def main() -> None:
    """Update the qoder-cli-cn package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]

    print("Fetching manifest from official source...")
    response = fetch_json(MANIFEST_URL)
    if not isinstance(response, dict):
        msg = "Manifest is not a JSON object"
        raise TypeError(msg)
    manifest: dict[str, Any] = response
    latest: str = manifest["latest"]

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating qoder-cli-cn from {current} to {latest}")

    # Extract URLs and hashes from manifest. Upstream has changed file naming
    # before, so we record the exact URL rather than reconstructing it.
    platforms: dict[str, dict[str, str]] = {}
    for file_entry in manifest["files"]:
        os_name = file_entry["os"]
        arch = file_entry["arch"]
        key = (os_name, arch)

        if key in PLATFORM_MAP:
            nix_platform = PLATFORM_MAP[key]
            platforms[nix_platform] = {
                "url": file_entry["url"],
                "hash": hex_to_sri(file_entry["sha256"]),
            }

    # Verify we got all expected platforms
    expected = set(PLATFORM_MAP.values())
    got = set(platforms.keys())
    missing = expected - got
    if missing:
        print(f"Warning: Missing platforms in manifest: {missing}")

    save_hashes(HASHES_FILE, {"version": latest, "platforms": platforms})
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
