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
    flake_attr: str | None = None,
    dep_hash_key: str | None = None,
    *,
    ref_prefix: str = "v",
) -> None:
    """Bump version/src hash and recalc dep_hash_key (e.g. Go vendorHash).

    A non-default ref_prefix becomes an x_tag_template qualifier, so prefixed
    release tags (``pkg-v1.2.3``) resolve to the bare version the package
    interpolates into its own ``rev``/``tag``.
    """
    if dep_hash_key and not flake_attr:
        msg = "github-source: depHashKey needs flakeAttr"
        raise ValueError(msg)

    hashes_file = pkg_dir / "hashes.json"
    data = load_hashes(hashes_file)
    current = data["version"]

    fetcher = PurlFetcher.default()
    purl = Purl("github", owner, repo)
    if ref_prefix != "v":
        purl = purl.with_qualifiers(x_tag_template=f"{ref_prefix}{{v}}")
    resolved = fetcher.resolve(purl)

    print(f"Current: {current}, Latest: {resolved.version}")

    if not should_update(current, resolved.version):
        print("Already up to date")
        return

    print("Calculating source hash...")
    source_hash = fetcher.hashes(purl, resolved)["src"]

    data = {"version": resolved.version, "hash": source_hash}
    if dep_hash_key:
        data[dep_hash_key] = DUMMY_SHA256_HASH
    save_hashes(hashes_file, data)

    if dep_hash_key:
        if flake_attr is None:
            msg = "github-source: depHashKey needs flakeAttr"
            raise ValueError(msg)
        update_dependency_hash(flake_attr, dep_hash_key, hashes_file, data)

    print(f"Updated to {resolved.version}")
