#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nodejs_24 --command python3

"""Update script for gno package.

Generates package-lock.json from upstream source (which uses bun.lock),
and stores version + hashes in hashes.json.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    extract_or_generate_lockfile,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import DUMMY_SHA256_HASH, extract_hash_from_build_error
from updater.nix import NixCommandError, nix_build

SCRIPT_DIR = Path(__file__).parent
HASHES_FILE = SCRIPT_DIR / "hashes.json"
OWNER = "gmickel"
REPO = "gno"
FLAKE_PACKAGE = ".#gno"


def main() -> None:
    """Update the gno package."""
    data = load_hashes(HASHES_FILE)
    current_version = data["version"]

    tag, latest_version = fetch_github_latest_release(OWNER, REPO)
    print(f"Current version: {current_version}")
    print(f"Latest version:  {latest_version} ({tag})")

    if not should_update(current_version, latest_version):
        print("Already up to date")
        return

    print(f"Updating gno to {latest_version}...")

    # Generate package-lock.json from upstream source
    tarball_url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/{tag}.tar.gz"
    extract_or_generate_lockfile(
        tarball_url=tarball_url,
        output_path=SCRIPT_DIR / "package-lock.json",
        extra_npm_flags=["--legacy-peer-deps"],
    )

    # Calculate source hash
    print(f"Calculating source hash for {tarball_url}...")
    src_hash = calculate_url_hash(tarball_url, unpack=True)
    print(f"  srcHash: {src_hash}")

    # Save with dummy npmDepsHash, then calculate via build
    save_hashes(
        HASHES_FILE,
        {
            "version": latest_version,
            "hash": src_hash,
            "npmDepsHash": DUMMY_SHA256_HASH,
        },
    )

    # Calculate npmDepsHash via dummy-hash-and-build pattern
    try:
        nix_build(FLAKE_PACKAGE, check=True)
        msg = "Build succeeded with dummy hash - unexpected"
        raise ValueError(msg)
    except NixCommandError as e:
        npm_deps_hash = extract_hash_from_build_error(e.args[0])
        if not npm_deps_hash:
            msg = f"Could not extract hash from build error:\n{e.args[0]}"
            raise ValueError(msg) from e

        save_hashes(
            HASHES_FILE,
            {
                "version": latest_version,
                "hash": src_hash,
                "npmDepsHash": npm_deps_hash,
            },
        )
        print(f"  npmDepsHash: {npm_deps_hash}")

    print(f"Updated to {latest_version}")


if __name__ == "__main__":
    main()
