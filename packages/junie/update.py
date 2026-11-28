"""Update script for junie package."""

import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import fetch_text, load_hashes, save_hashes, should_update
from updater.hash import hex_to_sri

HASHES_FILE = Path(__file__).parent / "hashes.json"
UPDATE_INFO_URL = (
    "https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl"
)

PLATFORMS = {
    "x86_64-linux": "linux-amd64",
    "aarch64-linux": "linux-aarch64",
    "aarch64-darwin": "macos-aarch64",
}


def version_key(version: str) -> tuple[int, ...]:
    """Convert dotted numeric version string to sortable key."""
    return tuple(int(part) for part in version.split("."))


def fetch_release_hashes() -> tuple[str, dict[str, str]]:
    """Fetch latest stable release with all required platforms."""
    content = fetch_text(UPDATE_INFO_URL)

    by_version: dict[str, dict[str, str]] = defaultdict(dict)
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        entry = json.loads(line)
        version = entry.get("version")
        platform = entry.get("platform")
        sha256_hex = entry.get("sha256")

        if (
            not isinstance(version, str)
            or not isinstance(platform, str)
            or not isinstance(sha256_hex, str)
        ):
            continue

        by_version[version][platform] = sha256_hex

    required_platforms = set(PLATFORMS.values())
    complete_versions = [
        version
        for version, platform_hashes in by_version.items()
        if required_platforms.issubset(platform_hashes)
    ]

    if not complete_versions:
        msg = "No Junie stable release found with all required platforms"
        raise RuntimeError(msg)

    latest = max(complete_versions, key=version_key)
    latest_hashes = by_version[latest]

    nix_hashes = {
        nix_platform: hex_to_sri(latest_hashes[upstream_platform])
        for nix_platform, upstream_platform in PLATFORMS.items()
    }

    return latest, nix_hashes


def main() -> None:
    """Update the junie package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest, hashes = fetch_release_hashes()

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        if data.get("hashes") != hashes:
            save_hashes(HASHES_FILE, {"version": latest, "hashes": hashes})
            print(f"Refreshed hashes for {latest}")
        else:
            print("Already up to date")
        return

    save_hashes(HASHES_FILE, {"version": latest, "hashes": hashes})
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
