"""Update script for icm (Infinite Context Memory) package.

This is a Tier 2 updater because it requires regenerating bun.nix (bun2nix lockfile)
in addition to updating source hashes and cargoHash. The standard nix-update tool
cannot handle bun2nix regeneration.

ICM's web frontend uses bun.lock located in crates/icm-cli/web/ (not at repo root),
so we define a local helper function to handle subdirectory bun.lock files.

Update flow:
1. Fetch latest release from GitHub (strips 'icm-v' prefix from tag)
2. Calculate new source hash for the tarball
3. Regenerate bun.nix from the subdirectory bun.lock
4. Calculate cargoHash by building with a dummy hash and extracting the real one
5. Save all hashes to hashes.json
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    load_hashes,
    regenerate_bun_nix,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent
HASHES_FILE = PKG_DIR / "hashes.json"
BUN_NIX = PKG_DIR / "bun.nix"

OWNER = "rtk-ai"
REPO = "icm"
BUN_LOCK_SUBDIR = "crates/icm-cli/web"


def clone_and_generate_bun_nix_subdir(
    owner: str,
    repo: str,
    version: str,
    bun_lock_subdir: str,
    bun_nix_output: Path,
    flake_root: Path,
    *,
    ref_prefix: str = "",
) -> None:
    """Clone a repo and regenerate bun.nix from a bun.lock in a subdirectory.

    This is a local helper function specific to ICM's directory structure.
    Unlike the standard clone_and_generate_bun_nix (which expects bun.lock
    at repo root), this function supports projects where the lockfile is
    in a subdirectory.

    Args:
        owner: GitHub repository owner
        repo: GitHub repository name
        version: Version tag or commit to check out
        bun_lock_subdir: Subdirectory containing bun.lock (relative to repo root)
        bun_nix_output: Path where bun.nix should be written
        flake_root: Root directory of the flake
        ref_prefix: Prefix for the git ref (e.g. "v" for "v1.0.0" tags)

    Raises:
        FileNotFoundError: If bun.lock not found in the specified subdirectory

    """
    ref = f"{ref_prefix}{version}"

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_dir = Path(tmpdir) / repo

        print(f"Cloning {owner}/{repo} at {ref}...")
        subprocess.run(
            [
                "git",
                "clone",
                "--depth=1",
                f"--branch={ref}",
                f"https://github.com/{owner}/{repo}.git",
                str(repo_dir),
            ],
            check=True,
            capture_output=True,
        )

        bun_lock = repo_dir / bun_lock_subdir / "bun.lock"
        if not bun_lock.exists():
            msg = (
                f"Could not find bun.lock at {bun_lock_subdir}/bun.lock in "
                f"{owner}/{repo} at {ref}"
            )
            raise FileNotFoundError(msg)

        regenerate_bun_nix(bun_lock, bun_nix_output, flake_root)


def main() -> None:
    """Update the icm package to the latest version.

    This function orchestrates the complete update process:

    1. **Fetch latest version**: Queries GitHub API for the latest release tag
       and strips the 'icm-v' prefix (e.g., 'icm-v0.10.50' -> '0.10.50')

    2. **Check if update needed**: Compares current version with latest using
       semantic versioning rules

    3. **Calculate source hash**: Downloads the source tarball and computes
       its SHA256 hash for fetchFromGitHub

    4. **Regenerate bun.nix**: Clones the repo, extracts bun.lock from the
       web frontend subdirectory, and runs bun2nix to regenerate bun.nix

    5. **Calculate cargoHash**: Builds the Rust package with a dummy hash,
       which fails and reveals the correct hash in the error message

    6. **Save hashes**: Writes version, hash, and cargoHash to hashes.json

    The script is idempotent - running it multiple times is safe. If the
    package is already up to date, it exits early with a message.
    """
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    # Strip 'icm-v' prefix from tag name
    if latest.startswith("icm-v"):
        latest = latest[5:]
    elif latest.startswith("v"):
        latest = latest[1:]

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating icm from {current} to {latest}")

    # Step 1: Calculate new source hash
    print("Calculating source hash...")
    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/icm-v{latest}.tar.gz"
    source_hash = calculate_url_hash(url, unpack=True)

    data = {
        "version": latest,
        "hash": source_hash,
        "cargoHash": DUMMY_SHA256_HASH,
    }
    save_hashes(HASHES_FILE, data)

    # Step 2: Regenerate bun.nix from upstream bun.lock (in subdirectory)
    print("Regenerating bun.nix...")
    clone_and_generate_bun_nix_subdir(
        owner=OWNER,
        repo=REPO,
        version=latest,
        bun_lock_subdir=BUN_LOCK_SUBDIR,
        bun_nix_output=BUN_NIX,
        flake_root=FLAKE_ROOT,
        ref_prefix="icm-v",
    )

    # Step 3: Calculate cargoHash
    print("Calculating cargoHash...")
    update_dependency_hash(".#icm", "cargoHash", HASHES_FILE, data)

    print(f"Updated icm to {latest}")


if __name__ == "__main__":
    main()
