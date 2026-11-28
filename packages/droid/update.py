"""Update script for droid package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    fetch_version_from_text,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"

PLATFORMS = {
    "x86_64-linux": "linux/x64",
    "aarch64-linux": "linux/arm64",
    "aarch64-darwin": "darwin/arm64",
}

VERSION_URL = "https://app.factory.ai/cli"
VERSION_PATTERN = r'VER="([^"]+)"'


def main() -> None:
    """Update the droid package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_version_from_text(VERSION_URL, VERSION_PATTERN)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    # Droid binaries
    droid_url_template = (
        f"https://downloads.factory.ai/factory-cli/releases/{latest}/{{platform}}/droid"
    )
    droid_hashes = calculate_platform_hashes(droid_url_template, PLATFORMS)

    # Ripgrep binaries (no version in URL)
    ripgrep_url_template = "https://downloads.factory.ai/ripgrep/{platform}/rg"
    ripgrep_hashes = calculate_platform_hashes(ripgrep_url_template, PLATFORMS)

    save_hashes(
        HASHES_FILE,
        {"version": latest, "droid": droid_hashes, "ripgrep": ripgrep_hashes},
    )
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
