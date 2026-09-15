"""Update flow for a version-templated JSON manifest of per-platform checksums.

Upstream ships a ``latest`` pointer plus ``{version}/manifest.json`` of hex
checksums; the build rebuilds the URL from the version.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from updater.hash import hex_to_sri
from updater.hashes_file import load_hashes, save_hashes
from updater.interpolate import interpolate, version_vars
from updater.version import should_update

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path


def _dig(obj: object, dotted_path: str) -> str:
    """Follow a dotted key path into nested dicts and return a string leaf."""
    current = obj
    for key in dotted_path.split("."):
        if not isinstance(current, dict):
            msg = f"manifest path {dotted_path!r} hit a non-object at {key!r}"
            raise TypeError(msg)
        current = current[key]
    if not isinstance(current, str):
        msg = f"manifest path {dotted_path!r} is not a string checksum"
        raise TypeError(msg)
    return current


def update_manifest_checksums(
    pkg_dir: Path,
    *,
    fetch_latest: Callable[[], str],
    manifest_url_template: str,
    checksum_path: str,
    platforms: dict[str, str],
    allow_downgrade: bool = False,
) -> None:
    """Bump version and per-platform hashes from a templated JSON manifest.

    ``checksum_path`` is a dotted path with a ``{platform}`` placeholder, e.g.
    ``platforms.{platform}.checksum``. ``platforms`` maps each nix system to its
    manifest token. ``allow_downgrade`` follows the pointer down too, for yanked
    releases.
    """
    hashes_file = pkg_dir / "hashes.json"
    data = load_hashes(hashes_file)
    current = data["version"]
    latest = fetch_latest()

    print(f"Current: {current}, Latest: {latest}")

    changed = current != latest if allow_downgrade else should_update(current, latest)
    if not changed:
        print("Already up to date")
        return

    from updater.http import fetch_json  # noqa: PLC0415 -- patched in tests

    manifest_url = interpolate(manifest_url_template, version_vars(latest))
    manifest = fetch_json(manifest_url)
    if not isinstance(manifest, dict):
        msg = f"expected a JSON object from {manifest_url}"
        raise TypeError(msg)

    hashes: dict[str, str] = {}
    for nix_platform, token in platforms.items():
        path = interpolate(checksum_path, {"platform": token})
        hashes[nix_platform] = hex_to_sri(_dig(manifest, path))
        print(f"  {nix_platform}: {hashes[nix_platform]}")

    save_hashes(hashes_file, {"version": latest, "hashes": hashes})
    print(f"Updated to {latest}")
