"""Update script for collie.

Custom updater because collie carries TWO bun lockfiles — the root bridge
and the Vite web UI — so both bun.nix files must be regenerated per bump.
"""

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

OWNER = "AltanS"
REPO = "collie"

pkg_dir = Path(__file__).parent
flake_root = pkg_dir.parent.parent

data = load_hashes(pkg_dir / "hashes.json")
current = data["version"]
latest = fetch_github_latest_release(OWNER, REPO)

print(f"Current: {current}, Latest: {latest}")

if not should_update(current, latest):
    print("Already up to date")
    sys.exit(0)

url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
src_hash = nix_prefetch_url(url, unpack=True)
save_hashes(pkg_dir / "hashes.json", {"version": latest, "hash": src_hash})

with tempfile.TemporaryDirectory() as tmpdir:
    repo_dir = Path(tmpdir) / REPO
    print(f"Cloning {OWNER}/{REPO} at v{latest}...")
    subprocess.run(
        [
            "git",
            "clone",
            "--depth=1",
            f"--branch=v{latest}",
            f"https://github.com/{OWNER}/{REPO}.git",
            str(repo_dir),
        ],
        check=True,
        capture_output=True,
    )

    for lock_dir, bun_nix in [
        (repo_dir, "bun.nix"),
        (repo_dir / "web", "web-bun.nix"),
    ]:
        # A stale lockfile makes bun hit the network inside the sandbox.
        subprocess.run(
            ["bun", "install", "--frozen-lockfile", "--lockfile-only"],
            cwd=lock_dir,
            check=True,
            capture_output=True,
        )
        regenerate_bun_nix(lock_dir / "bun.lock", pkg_dir / bun_nix, flake_root)

print(f"Updated to {latest}")
