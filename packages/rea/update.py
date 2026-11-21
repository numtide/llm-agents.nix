#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update REA from stable rea-agents releases, then pin its locked Frida assets."""

from __future__ import annotations

import json
import subprocess
import sys
from contextlib import ExitStack
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater.deps import update_dependency_hash
from updater.hash import DUMMY_SHA256_HASH, calculate_url_hash, hex_to_sri
from updater.hashes_file import load_hashes, save_hashes
from updater.http import fetch_json
from updater.nix import nix_store_prefetch_file
from updater.version import fetch_github_latest_release, should_update

PACKAGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_DIR.parents[1]
REA_ATTR = ".#rea"
ARCHITECTURES = {"x86_64-linux": "x64", "aarch64-linux": "arm64"}


def update_release(tag: str) -> None:
    """Pin the selected source and its npm dependencies as a pair."""
    version = tag.removeprefix("rea-agents-")
    path = PACKAGE_DIR / "hashes.json"
    pins = load_hashes(path)
    current = pins["version"]
    incomplete = current == version and pins["npmDepsHash"] == DUMMY_SHA256_HASH
    if not incomplete and not should_update(current, version):
        print(f"Keeping REA {current} (latest stable: {version})")
        return

    url = f"https://github.com/morluto/rea/archive/refs/tags/{tag}.tar.gz"
    pins.update(version=version, hash=calculate_url_hash(url, unpack=True))
    # Nix reads the candidate source from disk while computing npmDepsHash.
    with ExitStack() as rollback:
        rollback.callback(path.write_bytes, path.read_bytes())
        save_hashes(path, pins)
        update_dependency_hash(REA_ATTR, "npmDepsHash", path, pins)
        rollback.pop_all()


def locked_frida_version() -> str:
    """Read the Frida version REA's refreshed package-lock.json selects."""
    source = subprocess.check_output(
        ["nix", "build", f"{REA_ATTR}.src", "--no-link", "--print-out-paths"],
        text=True,
        cwd=REPO_ROOT,
    ).strip()
    lock = cast(
        "dict[str, Any]",
        json.loads((Path(source) / "package-lock.json").read_text()),
    )
    return cast("str", lock["packages"]["node_modules/frida"]["version"])


def reconcile_frida(version: str) -> None:
    """Point frida.json at the prebuilds matching ``version``."""
    pins_file = PACKAGE_DIR / "frida.json"
    pins = cast("dict[str, Any]", json.loads(pins_file.read_text()))
    if pins["version"] == version:
        return

    metadata = fetch_json(f"https://registry.npmjs.org/frida/{version}")
    if not isinstance(metadata, dict):
        msg = "expected Frida npm metadata to be an object"
        raise TypeError(msg)
    napi = max(metadata["binary"]["napi_versions"])
    release = fetch_json(
        f"https://api.github.com/repos/frida/frida/releases/tags/{version}"
    )
    if not isinstance(release, dict):
        msg = "expected Frida release metadata to be an object"
        raise TypeError(msg)
    assets = {asset["name"]: asset for asset in release["assets"]}

    hashes = {}
    for system, arch in ARCHITECTURES.items():
        name = f"frida-v{version}-napi-v{napi}-linux-{arch}.tar.gz"
        asset = assets[name]
        digest = asset.get("digest") or ""
        hashes[system] = (
            hex_to_sri(digest.removeprefix("sha256:"))
            if digest.startswith("sha256:")
            else nix_store_prefetch_file(asset["browser_download_url"])
        )
    pins_file.write_text(
        json.dumps(
            {"version": version, "napiVersion": napi, "hashes": hashes}, indent=2
        )
        + "\n"
    )


def main() -> None:
    """Refresh REA's hashes, then the Frida pins they imply."""
    tag = fetch_github_latest_release(
        "morluto", "rea", tag_pattern=r"rea-agents-[0-9]+\.[0-9]+\.[0-9]+"
    )
    update_release(tag)
    reconcile_frida(locked_frida_version())


if __name__ == "__main__":
    main()
