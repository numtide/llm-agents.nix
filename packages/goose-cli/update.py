"""Update script for goose-cli package.

Bumps the goose version, source hash and cargoHash in hashes.json and keeps
the librusty_v8 release hashes in sync with the v8 version pinned in goose's
Cargo.lock. Everything is driven through hashes.json because nix-update
cannot handle the extra librusty_v8 fixed-output derivation.
"""

import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"
# Upstream moved from block/goose to aaif-goose/goose.
OWNER = "aaif-goose"
REPO = "goose"

PLATFORMS = {
    "x86_64-linux": "x86_64-unknown-linux-gnu",
    "aarch64-linux": "aarch64-unknown-linux-gnu",
    "aarch64-darwin": "aarch64-apple-darwin",
}


def fetch_v8_version_from_cargo_lock(goose_version: str) -> str:
    """Extract the v8 version from goose's Cargo.lock file."""
    url = (
        f"https://raw.githubusercontent.com/{OWNER}/{REPO}/v{goose_version}/Cargo.lock"
    )
    cargo_lock = fetch_text(url)

    lines = cargo_lock.split("\n")
    for i, line in enumerate(lines):
        if line.strip() == 'name = "v8"':
            for j in range(i + 1, min(i + 10, len(lines))):
                if "version = " in lines[j]:
                    return lines[j].split('"')[1]

    msg = "Could not find v8 version in Cargo.lock"
    raise ValueError(msg)


def update_librusty_v8(data: dict[str, Any], goose_version: str) -> None:
    """Sync librustyV8 entry in hashes.json with goose's Cargo.lock."""
    v8_version = fetch_v8_version_from_cargo_lock(goose_version)
    current = data.get("librustyV8", {})
    if current.get("version") == v8_version:
        print(f"librusty_v8 already up to date ({v8_version})")
        return

    print(f"Updating librusty_v8 to {v8_version}")
    url_template = (
        f"https://github.com/denoland/rusty_v8/releases/download/"
        f"v{v8_version}/librusty_v8_release_{{platform}}.a.gz"
    )
    data["librustyV8"] = {
        "version": v8_version,
        "hashes": calculate_platform_hashes(url_template, PLATFORMS),
    }


def main() -> None:
    """Update the goose-cli package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)
    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    src_url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    data["version"] = latest
    data["hash"] = calculate_url_hash(src_url, unpack=True)
    data["cargoHash"] = DUMMY_SHA256_HASH
    update_librusty_v8(data, latest)
    save_hashes(HASHES_FILE, data)

    update_dependency_hash(".#goose-cli", "cargoHash", HASHES_FILE, data)

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
