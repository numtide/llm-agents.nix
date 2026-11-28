"""Update script for Antigravity CLI."""

import sys
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    fetch_json,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import hex_to_sri

HASHES_FILE = Path(__file__).parent / "hashes.json"
MANIFEST_BASE = (
    "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"
)
PLATFORMS = {
    "x86_64-linux": "linux_amd64",
    "aarch64-linux": "linux_arm64",
    "aarch64-darwin": "darwin_arm64",
}


def fetch_manifest(platform: str) -> dict[str, str]:
    """Fetch a platform release manifest."""
    result = fetch_json(f"{MANIFEST_BASE}/{platform}.json")
    manifest = cast("dict[str, Any]", result)
    return {
        "version": str(manifest["version"]),
        "url": str(manifest["url"]),
        "sha512": str(manifest["sha512"]),
    }


def main() -> None:
    """Update the Antigravity package."""
    data = load_hashes(HASHES_FILE)
    current = str(data["version"])
    first_manifest = fetch_manifest(PLATFORMS["x86_64-linux"])
    latest = first_manifest["version"]

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    urls = {}
    hashes = {}
    manifests = {"x86_64-linux": first_manifest}

    for nix_platform, manifest_platform in PLATFORMS.items():
        manifest = manifests.get(nix_platform) or fetch_manifest(manifest_platform)
        if manifest["version"] != latest:
            msg = f"{nix_platform} has version {manifest['version']}, expected {latest}"
            raise RuntimeError(msg)

        urls[nix_platform] = manifest["url"]
        hashes[nix_platform] = hex_to_sri(manifest["sha512"], "sha512")
        print(f"  {nix_platform}: {hashes[nix_platform]}")

    save_hashes(
        HASHES_FILE,
        {
            "version": latest,
            "urls": urls,
            "hashes": hashes,
        },
    )

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
