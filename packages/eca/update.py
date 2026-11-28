"""Update script for eca package."""

import sys
from pathlib import Path

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    nix_eval,
    save_hashes,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"

PLATFORMS = {
    "x86_64-linux": "linux-amd64",
    "aarch64-linux": "linux-aarch64",
    "aarch64-darwin": "macos-aarch64",
}


def main() -> None:
    """Update the eca package."""
    # Get current version
    current = nix_eval(".#eca.version")
    latest = fetch_github_latest_release("editor-code-assistant", "eca")

    if current == latest:
        print("eca is already up-to-date!")
        return

    print(f"Updating eca from {current} to {latest}")

    hashes: dict[str, str] = {"version": latest}

    for platform, url_arch in PLATFORMS.items():
        url = f"https://github.com/editor-code-assistant/eca/releases/download/{latest}/eca-native-{url_arch}.zip"
        print(f"Fetching hash for {platform}...")
        hashes[platform] = calculate_url_hash(url, unpack=False)

    # Also fetch hash for JAR file
    jar_url = f"https://github.com/editor-code-assistant/eca/releases/download/{latest}/eca.jar"
    print("Fetching hash for JAR...")
    hashes["jar"] = calculate_url_hash(jar_url, unpack=False)

    save_hashes(HASHES_FILE, hashes)
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
