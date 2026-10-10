#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3
"""Update grok-bot from Cursor's stable update feed.

Grok Bot ships as prebuilt Electron packages on downloads.cursor.com. The
Linux feed advertises an AppImage URL, but the product namespace and build id
are shared across artifacts, so this script rebuilds the conventional .deb
URLs and records them in hashes.json. The macOS zip lives under a
version-keyed path with no build id, so it is derived from the version alone.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"

# Stable client id so staged-rollout bucketing stays deterministic in CI.
FEED_CLIENT_ID = "22185624-86ef-492e-aa86-1c52baa96fdc"

# Feed platform -> (nix system, CDN arch dir, deb arch suffix)
PLATFORMS = {
    "linux-x64": ("x86_64-linux", "x64", "amd64"),
    "linux-arm64": ("aarch64-linux", "arm64", "arm64"),
}

DOWNLOAD_BASE_RE = re.compile(
    r"^(https://downloads\.cursor\.com/[a-z0-9-]+/stable)/([0-9a-f]{40})/"
)


def feed_url(platform: str) -> str:
    """Return Cursor's stable update-feed URL for a platform."""
    return (
        "https://api2.cursor.sh/updates/api/update/"
        f"{platform}/sand/0.0.1/{FEED_CLIENT_ID}/stable"
    )


def parse_download_location(artifact_url: str) -> tuple[str, str]:
    """Extract (download_base, build_id) from a feed artifact URL."""
    match = DOWNLOAD_BASE_RE.match(artifact_url)
    if not match:
        msg = f"unsupported artifact URL: {artifact_url}"
        raise RuntimeError(msg)
    return match.group(1), match.group(2)


def fetch_feed(platform: str) -> dict[str, str]:
    """Fetch one platform's stable feed, raising on empty/invalid responses."""
    url = feed_url(platform)
    print(f"checking {url}")
    try:
        data = fetch_json(url)
    except HTTPError as exc:
        msg = f"feed request failed for {platform}: HTTP {exc.code}"
        raise RuntimeError(msg) from exc
    except URLError as exc:
        msg = f"feed request failed for {platform}: {exc}"
        raise RuntimeError(msg) from exc

    if not isinstance(data, dict):
        msg = f"feed for {platform} returned non-object JSON"
        raise TypeError(msg)

    version = data.get("version") or data.get("name")
    artifact_url = data.get("url")
    if not isinstance(version, str) or not version:
        msg = f"feed for {platform} missing version"
        raise RuntimeError(msg)
    if not isinstance(artifact_url, str) or not artifact_url:
        msg = f"feed for {platform} missing url"
        raise RuntimeError(msg)

    return {"version": version, "url": artifact_url}


def deb_url(
    download_base: str, build_id: str, version: str, arch_dir: str, deb_arch: str
) -> str:
    """Return the .deb URL for one architecture."""
    return (
        f"{download_base}/{build_id}/linux/{arch_dir}/grok-bot_{version}_{deb_arch}.deb"
    )


def darwin_zip_url(download_base: str, version: str) -> str:
    """Return the notarized aarch64-darwin zip URL."""
    return f"{download_base}/darwin-arm64/{version}/Grok_Bot_{version}.zip"


def main() -> None:
    """Refresh hashes.json from the Cursor stable feed."""
    current = load_hashes(HASHES_FILE)

    # Prefer linux-x64 for shared version/buildId; fall back to arm64.
    shared = None
    last_error: Exception | None = None
    for platform in ("linux-x64", "linux-arm64"):
        try:
            feed = fetch_feed(platform)
            download_base, build_id = parse_download_location(feed["url"])
            shared = {
                "version": feed["version"],
                "download_base": download_base,
                "build_id": build_id,
            }
            break
        except Exception as exc:  # noqa: BLE001 - try next feed platform
            last_error = exc
            print(f"warning: {platform} feed unusable: {exc}")

    if shared is None:
        msg = f"no Linux update feed returned a usable response: {last_error}"
        raise RuntimeError(msg)

    version = shared["version"]
    download_base = shared["download_base"]
    build_id = shared["build_id"]

    # Staged rollouts can serve an older build; never move backwards.
    if not should_update(current["version"], version):
        print(f"grok-bot: already up to date ({current['version']}, feed: {version})")
        return

    urls: dict[str, str] = {}
    hashes: dict[str, str] = {}
    for nix_system, arch_dir, deb_arch in PLATFORMS.values():
        url = deb_url(download_base, build_id, version, arch_dir, deb_arch)
        print(f"prefetching {url}")
        urls[nix_system] = url
        hashes[nix_system] = calculate_url_hash(url)

    url = darwin_zip_url(download_base, version)
    print(f"prefetching {url}")
    urls["aarch64-darwin"] = url
    hashes["aarch64-darwin"] = calculate_url_hash(url)

    payload = {
        "version": version,
        "buildId": build_id,
        "urls": urls,
        "hashes": hashes,
    }

    save_hashes(HASHES_FILE, payload)
    print(f"Updated to {version} ({build_id})")


if __name__ == "__main__":
    main()
