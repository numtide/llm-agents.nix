#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update OpenCode 2 Desktop from its stable download redirect."""

import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import update_platform_binaries

LATEST_DESKTOP_URL = "https://opencode.ai/download/stable/darwin-aarch64-dmg"


def fetch_latest_version() -> str:
    """Read the desktop version from OpenCode's canonical stable redirect."""
    request = urllib.request.Request(LATEST_DESKTOP_URL)
    request.add_header("User-Agent", "llm-agents-updater")
    with urllib.request.urlopen(request, timeout=30) as response:
        final_url = response.url

    match = re.search(r"/files/bin/([^/]+)/opencode-desktop-", final_url)
    if not match:
        msg = f"Could not determine desktop version from redirect: {final_url}"
        raise ValueError(msg)
    return match.group(1)


update_platform_binaries(
    Path(__file__).parent,
    fetch_latest=fetch_latest_version,
    url_template="https://opencode.ai/files/bin/{version}/opencode-desktop-{platform}",
    platforms={
        "x86_64-linux": "linux-amd64.deb",
        "aarch64-linux": "linux-arm64.deb",
        "aarch64-darwin": "mac-arm64.dmg",
    },
)
