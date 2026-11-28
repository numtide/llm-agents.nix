"""Update script for the Cline CLI package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    calculate_url_hash,
    fetch_npm_version,
    load_hashes,
    save_hashes,
    should_update,
)

pkg_dir = Path(__file__).parent
hashes_file = pkg_dir / "hashes.json"
data = load_hashes(hashes_file)
current = data["version"]
latest = fetch_npm_version("cline")

print(f"Current: {current}, Latest: {latest}")

if not should_update(current, latest):
    print("Already up to date")
    raise SystemExit

platforms = {
    "x86_64-linux": "linux-x64",
    "aarch64-linux": "linux-arm64",
    "aarch64-darwin": "darwin-arm64",
}
hashes = calculate_platform_hashes(
    "https://registry.npmjs.org/@cline/cli-{platform}/-/cli-{platform}-{version}.tgz",
    platforms,
    version=latest,
)
launcher_hash = calculate_url_hash(
    f"https://registry.npmjs.org/cline/-/cline-{latest}.tgz"
)

save_hashes(
    hashes_file,
    {
        "version": latest,
        "launcherHash": launcher_hash,
        "hashes": hashes,
    },
)
print(f"Updated to {latest}")
