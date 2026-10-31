#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update WorkBuddy from its official macOS international and Linux CN channels.

The editions have independently versioned release channels. Hash the actual
downloads, retaining hashes for unchanged URLs to avoid downloading over a
gigabyte on every update check. Upstream's declared hashes can differ from the
downloaded archives. Separate per-platform APIs and versions do not fit the
shared declarative updater flows.
"""

import argparse
import sys
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import calculate_url_hash, fetch_json, load_hashes, save_hashes
from updater.version import compare_versions

HASHES_FILE = Path(__file__).parent / "hashes.json"
PLATFORMS = {
    "x86_64-linux": "workbuddy-linux-x64-deb",
    "aarch64-linux": "workbuddy-linux-arm64-deb",
    "aarch64-darwin": "workbuddy-darwin-arm64",
}


def fetch_release(platform: str, channel: str) -> tuple[str, str]:
    """Return a channel's version and official archive URL."""
    international = platform.endswith("-darwin")
    api_url = (
        "https://www.workbuddy.ai/v2/update"
        if international
        else "https://copilot.tencent.com/v2/update"
    )
    download_host = (
        "download.codebuddy.ai" if international else "download.codebuddy.cn"
    )
    release = fetch_json(f"{api_url}?platform={channel}")
    if not isinstance(release, dict):
        msg = f"{channel}: expected a release object"
        raise TypeError(msg)
    version = release.get("version")
    url = release.get("url")
    if not isinstance(version, str) or not version.strip():
        msg = f"{channel}: missing version"
        raise ValueError(msg)
    if not isinstance(url, str) or not url:
        msg = f"{channel}: missing download URL"
        raise ValueError(msg)
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != download_host:
        msg = f"{channel}: unexpected download URL: {url}"
        raise ValueError(msg)
    return version, url


def main(*, force: bool = False) -> None:
    """Refresh all channels, saving only after every fetch and hash succeeds."""
    current = load_hashes(HASHES_FILE)
    versions = {}
    urls = {}
    hashes = {}

    for platform, channel in PLATFORMS.items():
        version, url = fetch_release(platform, channel)
        previous_version = current.get("versions", {}).get(platform, "")
        if previous_version and compare_versions(version, previous_version) < 0:
            msg = f"{platform}: refusing downgrade from {previous_version} to {version}"
            raise RuntimeError(msg)

        versions[platform] = version
        urls[platform] = url
        recorded_hash = current.get("hashes", {}).get(platform)
        if (
            not force
            and version == previous_version
            and url == current.get("urls", {}).get(platform)
            and recorded_hash
        ):
            hashes[platform] = recorded_hash
        else:
            hashes[platform] = calculate_url_hash(url)
        print(f"{platform}: {version}")

    data = {
        "version": versions["x86_64-linux"],
        "versions": versions,
        "urls": urls,
        "hashes": hashes,
    }
    if data == current:
        print("workbuddy: already up to date")
        return

    save_hashes(HASHES_FILE, data)
    print("workbuddy: updated release metadata")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Refresh hashes even when release versions and URLs are unchanged",
    )
    main(force=parser.parse_args().force)
