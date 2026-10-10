"""Update flow for a version-templated JSON manifest of per-platform checksums.

Upstream ships a ``latest`` pointer plus ``{version}/manifest.json`` of hex
checksums; the build rebuilds the URL from the version.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from updater.hash import hex_to_sri
from updater.hashes_file import load_hashes, save_hashes
from updater.http import json_string_at_path
from updater.interpolate import interpolate, version_vars
from updater.version import should_update

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path


def update_manifest_checksums(
    pkg_dir: Path,
    *,
    fetch_latest: Callable[[], str],
    manifest_url_template: str,
    checksum_path: str,
    platforms: dict[str, str],
    allow_downgrade: bool = False,
    version_path: str | None = None,
) -> None:
    """Bump version and per-platform hashes from a templated JSON manifest.

    ``checksum_path`` is a dotted path with a ``{platform}`` placeholder, e.g.
    ``platforms.{platform}.checksum``. ``platforms`` maps each nix system to its
    manifest token. ``allow_downgrade`` follows the pointer down too, for yanked
    releases. When ``version_path`` is set, the version and checksums are read
    from the same response at ``manifest_url_template``.
    """
    hashes_file = pkg_dir / "hashes.json"
    data = load_hashes(hashes_file)
    current = data["version"]
    from updater.http import fetch_json  # noqa: PLC0415 -- patched in tests

    manifest = None
    if version_path is not None:
        manifest = fetch_json(manifest_url_template)
        latest = json_string_at_path(manifest, version_path)
    else:
        latest = fetch_latest()

    print(f"Current: {current}, Latest: {latest}")

    changed = current != latest if allow_downgrade else should_update(current, latest)
    if not changed:
        print("Already up to date")
        return

    manifest_url = interpolate(manifest_url_template, version_vars(latest))
    if manifest is None:
        manifest = fetch_json(manifest_url)
    if not isinstance(manifest, dict):
        msg = f"expected a JSON object from {manifest_url}"
        raise TypeError(msg)

    hashes: dict[str, str] = {}
    for nix_platform, token in platforms.items():
        path = interpolate(checksum_path, {"platform": token})
        hashes[nix_platform] = hex_to_sri(json_string_at_path(manifest, path))
        print(f"  {nix_platform}: {hashes[nix_platform]}")

    save_hashes(hashes_file, {"version": latest, "hashes": hashes})
    print(f"Updated to {latest}")
