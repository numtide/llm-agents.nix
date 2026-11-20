#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nix-update --command python3

"""Update REA and the Frida prebuilds selected by its dependency lockfile.

The standard source updater cannot refresh Frida's separately fetched native
bindings. Skip unchanged REA releases before invoking nix-update so prefixed
GitHub tags do not cause repeated npm cache downloads.
"""

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater import fetch_github_latest_release, should_update
from updater.hash import hex_to_sri
from updater.http import fetch_json
from updater.nix import nix_eval, nix_store_prefetch_file

PACKAGE_DIR = Path(__file__).resolve().parent
ARCHITECTURES = {"x86_64-linux": "x64", "aarch64-linux": "arm64"}


def main() -> None:
    """Refresh REA's source/dependency hashes and matching Frida prebuilds."""
    current = nix_eval(".#rea.version")
    tag = fetch_github_latest_release(
        "morluto", "rea", tag_pattern=r"rea-agents-\d+\.\d+\.\d+"
    )
    latest = tag.removeprefix("rea-agents-")
    if should_update(current, latest):
        subprocess.run(
            [
                "nix-update",
                "--flake",
                "rea",
                "--version",
                latest,
                "--version-regex",
                r"rea-agents-(.*)",
            ],
            check=True,
        )
    else:
        print(f"REA {current} is already up to date")

    # Reconcile pins even after an interrupted update left REA already current.
    source = subprocess.check_output(
        ["nix", "build", ".#rea.src", "--no-link", "--print-out-paths"],
        text=True,
    ).strip()
    lock = json.loads((Path(source) / "package-lock.json").read_text())
    version = lock["packages"]["node_modules/frida"]["version"]
    pins_file = PACKAGE_DIR / "frida.json"
    pins = json.loads(pins_file.read_text())
    if pins["version"] == version:
        return

    metadata = fetch_json(f"https://registry.npmjs.org/frida/{version}")
    if not isinstance(metadata, dict):
        msg = "Expected Frida npm metadata to be an object"
        raise TypeError(msg)
    napi = max(metadata["binary"]["napi_versions"])
    release = fetch_json(
        f"https://api.github.com/repos/frida/frida/releases/tags/{version}"
    )
    if not isinstance(release, dict):
        msg = "Expected Frida release metadata to be an object"
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


if __name__ == "__main__":
    main()
