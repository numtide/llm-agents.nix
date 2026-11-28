"""Update script for freebuff package (prebuilt binaries)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import fetch_npm_version, update_platform_binaries

update_platform_binaries(
    Path(__file__).parent,
    fetch_latest=lambda: fetch_npm_version("freebuff"),
    url_template="https://github.com/CodebuffAI/codebuff-community/releases/download/freebuff-v{version}/freebuff-{platform}.tar.gz",
    platforms={
        "x86_64-linux": "linux-x64",
        "aarch64-linux": "linux-arm64",
        "aarch64-darwin": "darwin-arm64",
    },
)
