"""Update script for aionui package.

Custom updater needed because aionui uses bun2nix: each upstream release can
change bun.lock, so bun.nix must be regenerated to keep the package buildable
and compatible with the automated update pipeline.
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    fetch_github_latest_release,
    load_hashes,
    regenerate_bun_nix,
    save_hashes,
    should_update,
)
from updater.nix import nix_prefetch_url

PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent
HASHES_FILE = PKG_DIR / "hashes.json"
BUN_NIX = PKG_DIR / "bun.nix"
BUN_LOCK = PKG_DIR / "bun.lock"

OWNER = "iOfficeAI"
REPO = "AionUi"

EXTRA_DEPENDENCIES = {
    "@codemirror/commands": "6.10.3",
    "@codemirror/lang-html": "6.4.11",
    "@codemirror/view": "6.41.0",
    "@xmldom/xmldom": "0.9.9",
    "beautiful-mermaid": "1.1.3",
    "dayjs": "1.11.20",
    "https-proxy-agent": "9.0.0",
    "jszip": "3.10.1",
    "png-chunk-text": "1.0.0",
    "png-chunks-extract": "1.0.0",
    "tree-sitter-bash": "0.25.1",
    "yauzl": "3.3.0",
}


def regenerate_bun_artifacts(version: str) -> None:
    """Clone upstream, inject missing deps, and regenerate bun.lock/bun.nix."""
    ref = f"v{version}"

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_dir = Path(tmpdir) / REPO

        print(f"Cloning {OWNER}/{REPO} at {ref}...")
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

        package_json_path = repo_dir / "package.json"
        package_json = json.loads(package_json_path.read_text())
        package_json.setdefault("dependencies", {}).update(EXTRA_DEPENDENCIES)
        package_json_path.write_text(json.dumps(package_json, indent=2) + "\n")

        print("Refreshing bun.lock with downstream dependency fixes...")
        subprocess.run(
            ["bun", "install", "--lockfile-only"],
            cwd=repo_dir,
            check=True,
            capture_output=True,
        )

        shutil.copy2(repo_dir / "bun.lock", BUN_LOCK)
        regenerate_bun_nix(BUN_LOCK, BUN_NIX, FLAKE_ROOT)


def main() -> None:
    """Update the aionui package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating aionui from {current} to {latest}")

    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    src_hash = nix_prefetch_url(url, unpack=True)
    print(f"  source hash: {src_hash}")

    save_hashes(HASHES_FILE, {"version": latest, "hash": src_hash})
    print("Updated hashes.json")

    regenerate_bun_artifacts(latest)

    print(f"Updated aionui to {latest}")


if __name__ == "__main__":
    main()
