"""Update script for parallel-cli and its vendored Python dependencies."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
)

HASHES_FILE = Path(__file__).parent / "hashes.json"

# Each tuple: hashes.json key (None = top-level), GitHub owner, GitHub repo.
PACKAGES = [
    (None, "parallel-web", "parallel-web-tools"),
    ("parallelWeb", "parallel-web", "parallel-sdk-python"),
    ("sqlalchemyBigquery", "googleapis", "python-bigquery-sqlalchemy"),
]


def github_hash(owner: str, repo: str, version: str) -> str:
    """Prefetch the GitHub v-tagged release tarball hash."""
    url = f"https://github.com/{owner}/{repo}/archive/refs/tags/v{version}.tar.gz"
    return calculate_url_hash(url, unpack=True)


def main() -> None:
    """Update parallel-cli and vendored dependencies to latest releases."""
    data = load_hashes(HASHES_FILE)
    changed = False

    for key, owner, repo in PACKAGES:
        entry = data if key is None else data[key]
        current = entry["version"]
        latest = fetch_github_latest_release(owner, repo)
        print(f"{repo}: current={current}, latest={latest}")

        if should_update(current, latest):
            entry["version"] = latest
            entry["hash"] = github_hash(owner, repo, latest)
            changed = True

    if not changed:
        print("Already up to date")
        return

    save_hashes(HASHES_FILE, data)
    print(f"Updated parallel-cli to {data['version']}")


if __name__ == "__main__":
    main()
