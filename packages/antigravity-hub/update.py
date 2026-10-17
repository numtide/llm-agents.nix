#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for Antigravity Hub (Antigravity 2.0)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"
MANIFEST_BASE = (
    "https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest"
)

PLATFORMS = {
    "x86_64-linux": {"platform": "linux-x64", "ext": "tar.gz"},
    "aarch64-linux": {"platform": "linux-arm", "ext": "tar.gz"},
    "aarch64-darwin": {"platform": "darwin-arm", "ext": "zip"},
}

MANIFEST_URL_RE = re.compile(r"/antigravity-hub/([0-9.]+)-([0-9]+)/")


def read_manifest(manifest_name: str) -> tuple[str, str]:
    """Fetch a manifest and extract (version, build_id)."""
    text = fetch_text(f"{MANIFEST_BASE}/{manifest_name}.yml")
    match = MANIFEST_URL_RE.search(text)
    if not match:
        msg = f"Could not find version and buildId in manifest {manifest_name}"
        raise RuntimeError(msg)
    return match.group(1), match.group(2)


def download_url(version: str, build_id: str, platform: str, ext: str) -> str:
    """Construct download URL for a given platform."""
    return (
        "https://storage.googleapis.com/antigravity-public/antigravity-hub/"
        f"{version}-{build_id}/{platform}/Antigravity.{ext}"
    )


def main() -> None:
    """Update Antigravity Hub version and hashes."""
    data = load_hashes(HASHES_FILE)
    current = str(data["version"])

    linux_version, linux_build_id = read_manifest("latest-x64-linux")
    mac_version, mac_build_id = read_manifest("latest-arm64-mac")

    if (linux_version, linux_build_id) != (mac_version, mac_build_id):
        msg = (
            f"Linux ({linux_version}-{linux_build_id}) and macOS "
            f"({mac_version}-{mac_build_id}) releases differ, not updating"
        )
        raise RuntimeError(msg)

    latest = linux_version
    build_id = linux_build_id

    print(f"Current: {current}, Latest: {latest} ({build_id})")

    if not should_update(current, latest):
        print("Already up to date")
        return

    platforms_data: dict[str, dict[str, str]] = {}
    for nix_system, target in PLATFORMS.items():
        url = download_url(latest, build_id, target["platform"], target["ext"])
        print(f"  prefetching {nix_system} ({url})...")
        h = calculate_url_hash(url)
        platforms_data[nix_system] = {
            "platform": target["platform"],
            "hash": h,
        }

    save_hashes(
        HASHES_FILE,
        {
            "version": latest,
            "buildId": build_id,
            "platforms": platforms_data,
        },
    )

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
