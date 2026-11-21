"""Update flow for packages built from a GitHub release source tarball."""

from __future__ import annotations

from typing import TYPE_CHECKING

from updater.deps import update_dependency_hash
from updater.fetch import PurlFetcher
from updater.hash import DUMMY_SHA256_HASH
from updater.hashes_file import load_hashes, save_hashes
from updater.purl import Purl
from updater.version import should_update

if TYPE_CHECKING:
    from pathlib import Path


def update_github_source(
    pkg_dir: Path,
    owner: str,
    repo: str,
    flake_attr: str,
    dep_hash_key: str,
) -> None:
    """Bump version/src hash and recalc dep_hash_key (e.g. Go vendorHash)."""
    hashes_file = pkg_dir / "hashes.json"
    data = load_hashes(hashes_file)
    current = data["version"]

    fetcher = PurlFetcher.default()
    purl = Purl("github", owner, repo)
    resolved = fetcher.resolve(purl)

    print(f"Current: {current}, Latest: {resolved.version}")

    if not should_update(current, resolved.version):
        print("Already up to date")
        return

    print("Calculating source hash...")
    source_hash = fetcher.hashes(purl, resolved)["src"]

    data = {
        "version": resolved.version,
        "hash": source_hash,
        dep_hash_key: DUMMY_SHA256_HASH,
    }
    save_hashes(hashes_file, data)

    update_dependency_hash(flake_attr, dep_hash_key, hashes_file, data)

    print(f"Updated to {resolved.version}")
