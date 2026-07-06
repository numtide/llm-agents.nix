#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#bun nixpkgs#git --command python3

"""Update script for plannotator package."""

import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_dependency_hash,
    calculate_url_hash,
    clone_and_generate_bun_nix,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
    strip_workspace_entries,
)
from updater.hash import DUMMY_SHA256_HASH

PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent
HASHES_FILE = PKG_DIR / "hashes.json"
BUN_NIX = PKG_DIR / "bun.nix"
STALE_LOCK_PATCH = PKG_DIR / "fix-stale-bun-lock.patch"

OWNER = "backnotprop"
REPO = "plannotator"
SEM_OWNER = "Ataraxy-Labs"
SEM_REPO = "sem"
LATEST_RELEASE_URL = f"https://github.com/{OWNER}/{REPO}/releases/latest"


def fetch_latest_version() -> str:
    """Fetch the latest plannotator release via GitHub's redirect."""
    req = urllib.request.Request(LATEST_RELEASE_URL)
    req.add_header("User-Agent", "llm-agents-updater")
    with urllib.request.urlopen(req, timeout=30) as response:
        final_url = response.url

    match = re.search(r"/releases/tag/v?([^/?#]+)", final_url)
    if not match:
        msg = f"Could not determine latest version from redirect: {final_url}"
        raise ValueError(msg)
    return match.group(1)


def fetch_sem_version(plannotator_version: str) -> str:
    """Fetch the sem version expected by this plannotator release."""
    url = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/v{plannotator_version}/packages/shared/semantic-diff.ts"
    text = fetch_text(url)
    match = re.search(r'PLANNOTATOR_SEM_VERSION\s*=\s*"v([^"]+)"', text)
    if not match:
        msg = f"Could not find PLANNOTATOR_SEM_VERSION in {url}"
        raise ValueError(msg)
    return match.group(1)


def github_source_hash(owner: str, repo: str, version: str) -> str:
    """Calculate the unpacked GitHub tag archive hash."""
    url = f"https://github.com/{owner}/{repo}/archive/refs/tags/v{version}.tar.gz"
    return calculate_url_hash(url, unpack=True)


def refresh_stale_lock_patch(version: str) -> None:
    """Write the bun.lock refresh patch produced by Bun, if any."""
    ref = f"v{version}"
    with tempfile.TemporaryDirectory() as tmpdir:
        repo_dir = Path(tmpdir) / REPO
        print(f"Checking bun.lock refresh diff for {OWNER}/{REPO} {ref}...")
        subprocess.run(
            [
                "git",
                "clone",
                "--depth=1",
                f"--branch={ref}",
                f"https://github.com/{OWNER}/{REPO}.git",
                str(repo_dir),
            ],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["bun", "install", "--lockfile-only"],
            cwd=repo_dir,
            check=True,
            capture_output=True,
        )
        diff = subprocess.run(
            ["git", "diff", "--", "bun.lock"],
            cwd=repo_dir,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        STALE_LOCK_PATCH.write_text(diff)
        if diff:
            print(f"  wrote {STALE_LOCK_PATCH.name}")
        else:
            print("  bun.lock is fresh")


def main() -> None:
    """Update the plannotator package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_latest_version()

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating plannotator from {current} to {latest}")

    print("Calculating plannotator source hash...")
    source_hash = github_source_hash(OWNER, REPO, latest)
    print(f"  source hash: {source_hash}")

    sem_version = fetch_sem_version(latest)
    print(f"Calculating sem {sem_version} source hash...")
    sem_hash = github_source_hash(SEM_OWNER, SEM_REPO, sem_version)
    print(f"  sem hash: {sem_hash}")

    data = {
        "version": latest,
        "hash": source_hash,
        "semVersion": sem_version,
        "semHash": sem_hash,
        "semCargoHash": DUMMY_SHA256_HASH,
    }
    save_hashes(HASHES_FILE, data)

    data["semCargoHash"] = calculate_dependency_hash(
        package_attr=".#plannotator",
        hash_key="semCargoHash",
        hashes_file=HASHES_FILE,
        data=data,
    )
    save_hashes(HASHES_FILE, data)
    print(f"  sem cargoHash: {data['semCargoHash']}")

    clone_and_generate_bun_nix(
        OWNER,
        REPO,
        latest,
        BUN_NIX,
        FLAKE_ROOT,
        ref_prefix="v",
    )
    strip_workspace_entries(BUN_NIX, "@plannotator", FLAKE_ROOT)
    refresh_stale_lock_patch(latest)

    print(f"Updated plannotator to {latest}")


if __name__ == "__main__":
    main()
