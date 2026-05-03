#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for vibe-kanban package."""

import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_dependency_hash,
    calculate_url_hash,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import DUMMY_SHA256_HASH
from updater.nix import NixCommandError, nix_prefetch_url

HASHES_FILE = Path(__file__).parent / "hashes.json"


def fetch_latest_release_tag(owner: str, repo: str) -> tuple[str, str]:
    """Return (tag, version) of the latest BloopAI/vibe-kanban release.

    Tags are shaped `v0.1.44-20260424091429`. Strip the leading `v` and the
    timestamp suffix to derive the upstream semver.
    """
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    req = urllib.request.Request(url, headers={"User-Agent": "llm-agents-updater"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    tag = data["tag_name"]
    version = tag.lstrip("v").split("-", 1)[0]
    return tag, version


def main() -> None:
    """Update the vibe-kanban package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    tag, latest = fetch_latest_release_tag("BloopAI", "vibe-kanban")

    print(f"Current: {current}, Latest: {latest} (tag {tag})")

    if not should_update(current, latest):
        print("Already up to date")
        return

    src_url = f"https://github.com/BloopAI/vibe-kanban/archive/refs/tags/{tag}.tar.gz"
    print("Calculating source hash...")
    source_hash = calculate_url_hash(src_url, unpack=True)

    release_zip_url = (
        f"https://github.com/BloopAI/vibe-kanban/releases/download/{tag}/"
        f"vibe-kanban-{tag}.zip"
    )
    print("Calculating release zip hash...")
    release_zip_hash = nix_prefetch_url(release_zip_url, unpack=False)

    new_data = {
        "version": latest,
        "tag": tag,
        "hash": source_hash,
        "cargoHash": DUMMY_SHA256_HASH,
        "npmDepsHash": DUMMY_SHA256_HASH,
        "releaseZipHash": release_zip_hash,
    }
    save_hashes(HASHES_FILE, new_data)

    try:
        print("Calculating cargoHash...")
        cargo_hash = calculate_dependency_hash(
            ".#vibe-kanban", "cargoHash", HASHES_FILE, new_data
        )
        new_data["cargoHash"] = cargo_hash
        save_hashes(HASHES_FILE, new_data)

        print("Calculating npmDepsHash...")
        npm_deps_hash = calculate_dependency_hash(
            ".#vibe-kanban", "npmDepsHash", HASHES_FILE, new_data
        )
        new_data["npmDepsHash"] = npm_deps_hash
        save_hashes(HASHES_FILE, new_data)
    except (ValueError, NixCommandError) as e:
        print(f"Error: {e}")
        return

    print(f"Updated to {latest} (tag {tag})")


if __name__ == "__main__":
    main()
