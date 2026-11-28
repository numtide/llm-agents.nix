"""Update qwen-code to the newest stable CLI tag.

The repository also publishes SDK, desktop and nightly releases, so neither
/releases/latest nor the (truncated) releases list identifies the CLI. Git
tags are complete.
"""

import re
import subprocess
import sys
from functools import cmp_to_key
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import should_update
from updater.nix import nix_eval
from updater.version import compare_versions

REPO_URL = "https://github.com/QwenLM/qwen-code.git"
TAG_RE = re.compile(r"refs/tags/v(\d+\.\d+\.\d+)")


def fetch_latest_version() -> str:
    """Return the highest stable vX.Y.Z tag of the repository."""
    out = subprocess.run(
        ["git", "ls-remote", "--tags", "--refs", REPO_URL],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    versions = [
        m.group(1)
        for line in out.splitlines()
        if (m := TAG_RE.fullmatch(line.split()[1]))
    ]
    if not versions:
        sys.exit(f"no stable tags found in {REPO_URL}")
    return max(versions, key=cmp_to_key(compare_versions))


def main() -> None:
    """Update qwen-code if a newer stable CLI tag exists."""
    current = nix_eval(".#qwen-code.version")
    latest = fetch_latest_version()
    print(f"Current: {current}, Latest: {latest}")
    if should_update(current, latest):
        subprocess.run(
            ["nix-update", "--flake", "qwen-code", "--version", latest], check=True
        )


if __name__ == "__main__":
    main()
