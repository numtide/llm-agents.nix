#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nodejs_24 --command python3

"""Update script for gno package.

Handles package-lock.json generation (upstream uses bun.lockb)
and inline hash updates in package.nix.
"""

import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from urllib.request import urlretrieve

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import calculate_url_hash, fetch_json
from updater.hash import DUMMY_SHA256_HASH, extract_hash_from_build_error
from updater.nix import NixCommandError, nix_build

SCRIPT_DIR = Path(__file__).parent
PACKAGE_NIX = SCRIPT_DIR / "package.nix"
OWNER = "gmickel"
REPO = "gno"
FLAKE_PACKAGE = ".#gno"


def read_current_version() -> str:
    """Read current version from package.nix."""
    content = PACKAGE_NIX.read_text()
    match = re.search(r'^\s*version\s*=\s*"([^"]+)"', content, re.MULTILINE)
    if not match:
        msg = "Could not find version in package.nix"
        raise ValueError(msg)
    return match.group(1)


def extract_hash(pattern: str) -> str:
    """Extract a hash from package.nix using a regex pattern.

    The pattern must have a capture group for the hash value.
    """
    content = PACKAGE_NIX.read_text()
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        msg = f"Could not find hash with pattern: {pattern}"
        raise ValueError(msg)
    return match.group(1)


def replace_in_nix(old: str, new: str) -> None:
    """Replace a string in package.nix (first occurrence)."""
    content = PACKAGE_NIX.read_text()
    if old not in content:
        msg = f"String not found in package.nix: {old}"
        raise ValueError(msg)
    content = content.replace(old, new, 1)
    PACKAGE_NIX.write_text(content)


def fetch_latest_release() -> tuple[str, str]:
    """Fetch the latest release tag and version from GitHub.

    Returns:
        Tuple of (tag name e.g. "v0.16.0", version e.g. "0.16.0")

    """
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/releases/latest"
    data = fetch_json(url)
    if not isinstance(data, dict):
        msg = f"Expected dict from GitHub API, got {type(data)}"
        raise TypeError(msg)

    tag_name = data["tag_name"]
    version = tag_name.lstrip("v")
    return tag_name, version


def generate_lockfile_from_github(tag: str, output_path: Path) -> bool:
    """Generate package-lock.json from GitHub tarball.

    Downloads the GitHub tarball, extracts package.json, and generates
    package-lock.json.

    Args:
        tag: Git tag (e.g. "v0.16.0")
        output_path: Path where package-lock.json should be written

    Returns:
        True if lockfile was successfully generated, False otherwise

    """
    print("Generating package-lock.json from GitHub tarball...")

    tarball_url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/{tag}.tar.gz"

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        tarball_path = tmpdir_path / "package.tgz"
        urlretrieve(tarball_url, tarball_path)

        with tarfile.open(tarball_path, "r:gz") as tar:
            tar.extractall(tmpdir_path, filter="data")

        # GitHub archives extract to {repo}-{version}/
        package_dirs = list(tmpdir_path.glob(f"{REPO}-*"))
        if not package_dirs:
            print("ERROR: Could not find extracted package directory!")
            return False

        package_dir = package_dirs[0]
        package_json = package_dir / "package.json"

        if not package_json.exists():
            print("ERROR: No package.json found!")
            return False

        # Generate package-lock.json using pinned nodejs_24 (from nix shell shebang)
        result = subprocess.run(
            [
                "npm",
                "install",
                "--package-lock-only",
                "--ignore-scripts",
                "--legacy-peer-deps",
            ],
            cwd=package_dir,
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            print(f"ERROR: npm install failed:\n{result.stderr}")
            return False

        new_lock = package_dir / "package-lock.json"
        if new_lock.exists():
            output_path.write_text(new_lock.read_text())
            print("Generated package-lock.json")
            return True

        print("ERROR: Failed to generate package-lock.json")
        return False


def calculate_npm_deps_hash() -> str:
    """Calculate npmDepsHash using dummy-hash-and-build pattern."""
    current_hash = extract_hash(
        r'fetchNpmDepsWithPackuments\s*\{.*?hash\s*=\s*"([^"]+)"'
    )

    replace_in_nix(current_hash, DUMMY_SHA256_HASH)

    try:
        nix_build(FLAKE_PACKAGE, check=True)
        # Unexpected success — restore original
        replace_in_nix(DUMMY_SHA256_HASH, current_hash)
        msg = "Build succeeded with dummy hash - unexpected"
        raise ValueError(msg)
    except NixCommandError as e:
        dep_hash = extract_hash_from_build_error(e.args[0])
        if not dep_hash:
            replace_in_nix(DUMMY_SHA256_HASH, current_hash)
            msg = f"Could not extract hash from build error:\n{e.args[0]}"
            raise ValueError(msg) from e

        replace_in_nix(DUMMY_SHA256_HASH, dep_hash)
        print(f"  npmDepsHash: {dep_hash}")
        return dep_hash


def main() -> None:
    """Update the gno package."""
    current_version = read_current_version()

    tag, latest_version = fetch_latest_release()
    print(f"Current version: {current_version}")
    print(f"Latest version:  {latest_version} ({tag})")

    if current_version == latest_version:
        print("Already up to date")
        return

    print(f"Updating gno to {latest_version}...")

    # Generate package-lock.json for the new version
    if not generate_lockfile_from_github(tag, SCRIPT_DIR / "package-lock.json"):
        return

    # Update version in package.nix
    replace_in_nix(
        f'version = "{current_version}"',
        f'version = "{latest_version}"',
    )

    # Calculate and update srcHash
    old_src_hash = extract_hash(r'fetchFromGitHub\s*\{.*?hash\s*=\s*"([^"]+)"')
    tarball_url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/{tag}.tar.gz"
    print(f"Calculating source hash for {tarball_url}...")
    new_src_hash = calculate_url_hash(tarball_url, unpack=True)
    print(f"  srcHash: {new_src_hash}")
    replace_in_nix(old_src_hash, new_src_hash)

    # Calculate and update npmDepsHash
    try:
        calculate_npm_deps_hash()
    except ValueError as e:
        print(f"Failed to calculate npmDepsHash: {e}")
        return

    print(f"Updated to {latest_version}")


if __name__ == "__main__":
    main()
