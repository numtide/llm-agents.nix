"""Update flow for packages built from a GitHub release source tarball."""

from __future__ import annotations

from contextlib import ExitStack
from typing import TYPE_CHECKING

from updater.deps import update_dependency_hash
from updater.fetch import PurlFetcher
from updater.hash import DUMMY_SHA256_HASH
from updater.hashes_file import load_hashes, save_hashes
from updater.purl import Purl
from updater.version import should_update

if TYPE_CHECKING:
    from pathlib import Path

    from updater.fetch import Resolved


def update_github_source(
    pkg_dir: Path,
    owner: str,
    repo: str,
    flake_attr: str,
    dep_hash_key: str,
    *,
    release: Resolved | None = None,
) -> None:
    """Refresh source and dependency pins for a selected or latest release."""
    hashes_file = pkg_dir / "hashes.json"
    data = load_hashes(hashes_file)
    current = data["version"]

    fetcher = PurlFetcher.default()
    purl = Purl("github", owner, repo)
    resolved = release or fetcher.resolve(purl)

    print(f"Current: {current}, Latest: {resolved.version}")

    incomplete = current == resolved.version and data[dep_hash_key] == DUMMY_SHA256_HASH
    if not incomplete and not should_update(current, resolved.version):
        print("Already up to date")
        return

    print("Calculating source hash...")
    source_hash = fetcher.hashes(purl, resolved)["src"]

    # Nix must see the candidate pins while computing the dependency hash.
    # On failure restore the entire file, not just the already-staged dummy.
    with ExitStack() as rollback:
        rollback.callback(hashes_file.write_bytes, hashes_file.read_bytes())
        data.update(version=resolved.version, hash=source_hash)
        data[dep_hash_key] = DUMMY_SHA256_HASH
        save_hashes(hashes_file, data)
        update_dependency_hash(flake_attr, dep_hash_key, hashes_file, data)
        rollback.pop_all()

    print(f"Updated to {resolved.version}")
