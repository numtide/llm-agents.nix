"""Update opencodex: npm tarball + bun.lock from the matching git tag."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_npm_version,
    fetch_text,
    load_hashes,
    regenerate_bun_nix,
    save_hashes,
    should_update,
)

PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent
NPM = "@bitkyc08/opencodex"
REPO = "lidge-jun/opencodex"


def main() -> None:
    """Bump hashes.json, refresh bun.lock and bun.nix."""
    data = load_hashes(PKG_DIR / "hashes.json")
    latest = fetch_npm_version(NPM)
    print(f"Current: {data['version']}, Latest: {latest}")
    if not should_update(data["version"], latest):
        print("Already up to date")
        return

    url = f"https://registry.npmjs.org/{NPM}/-/opencodex-{latest}.tgz"
    save_hashes(
        PKG_DIR / "hashes.json",
        {"version": latest, "hash": calculate_url_hash(url)},
    )

    lock = PKG_DIR / "bun.lock"
    lock.write_text(
        fetch_text(f"https://raw.githubusercontent.com/{REPO}/v{latest}/bun.lock")
    )
    regenerate_bun_nix(lock, PKG_DIR / "bun.nix", FLAKE_ROOT)
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
