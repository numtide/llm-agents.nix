"""Update flow for packages built from an npm registry tarball."""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING

from updater.deps import update_dependency_hash
from updater.fetch import PurlFetcher
from updater.hash import DUMMY_SHA256_HASH
from updater.hashes_file import load_hashes, save_hashes
from updater.npm import extract_or_generate_lockfile
from updater.purl import Purl
from updater.version import should_update

if TYPE_CHECKING:
    from pathlib import Path


def _npm_purl(npm_package: str, *, fetchzip: bool, dist_tag: str | None = None) -> Purl:
    """Build the pkg:npm purl for a (possibly scoped) package name."""
    if npm_package.startswith("@"):
        scope, _, name = npm_package.partition("/")
        purl = Purl("npm", scope, name)
    else:
        purl = Purl("npm", None, npm_package)
    if dist_tag:
        # Track a non-default registry dist-tag (e.g. beta channels).
        purl = purl.with_qualifiers(x_dist_tag=dist_tag)
    # fetchzip hashes the unpacked tarball; flag it so source_hash unpacks.
    return purl.with_qualifiers(x_unpack="true") if fetchzip else purl


def update_npm_package(  # noqa: PLR0913 -- declarative passthru.updater config fields map 1:1
    pkg_dir: Path,
    npm_package: str,
    flake_attr: str,
    *,
    dist_tag: str | None = None,
    lockfile_env: dict[str, str] | None = None,
    strip_dev_dependencies: bool = False,
    require_lockfile: bool = True,
    fetchzip: bool = False,
    supplement_optional_deps: bool = False,
) -> None:
    """Bump version/hash, refresh package-lock.json, recalc npmDepsHash.

    fetchzip=True hashes the unpacked tarball and stores it under "hash"
    instead of "sourceHash" (for derivations using fetchzip, not fetchurl).
    dist_tag tracks a non-default npm dist-tag instead of "latest".
    """
    hashes_file = pkg_dir / "hashes.json"
    data = load_hashes(hashes_file)
    current = data["version"]

    fetcher = PurlFetcher.default()
    purl = _npm_purl(npm_package, fetchzip=fetchzip, dist_tag=dist_tag)
    resolved = fetcher.resolve(purl)

    print(f"Current: {current}, Latest: {resolved.version}")

    if not should_update(current, resolved.version):
        print("Already up to date")
        return

    handler = fetcher.handler(purl)
    location = handler.locations(purl, resolved)[0]

    print("Calculating source hash...")
    source_hash = handler.source_hash(location)

    if not extract_or_generate_lockfile(
        location.url,
        pkg_dir / "package-lock.json",
        env=lockfile_env,
        strip_dev_dependencies=strip_dev_dependencies,
        supplement_optional_deps=supplement_optional_deps,
    ):
        if require_lockfile:
            sys.exit(1)
        print("Warning: Failed to generate lockfile, continuing anyway...")

    # Dummy npmDepsHash; update_dependency_hash swaps in the real one from
    # the failed build's reported hash.
    source_hash_key = "hash" if fetchzip else "sourceHash"
    data = {
        "version": resolved.version,
        source_hash_key: source_hash,
        "npmDepsHash": DUMMY_SHA256_HASH,
    }
    save_hashes(hashes_file, data)

    print("Calculating npm dependencies hash...")
    update_dependency_hash(flake_attr, "npmDepsHash", hashes_file, data)

    print(f"Updated to {resolved.version}")
