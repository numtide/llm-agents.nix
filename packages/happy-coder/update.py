"""Update script for happy-coder.

Upstream is the slopus/happy pnpm-workspaces monorepo, which does not tag
the CLI. We track the ``happy`` npm version and build from the monorepo
commit that bumped ``packages/happy-cli/package.json`` to that version.
"""

import json
import sys
import urllib.request
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    fetch_json,
    fetch_npm_version,
    load_hashes,
    should_update,
    update_dependency_hash,
)
from updater.nix import nix_command

SCRIPT_DIR = Path(__file__).parent
HASHES_FILE = SCRIPT_DIR / "hashes.json"
NPM_PACKAGE = "happy"
MONOREPO = "slopus/happy"
CLI_PACKAGE_JSON = "packages/happy-cli/package.json"


def find_release_commit(version: str) -> str:
    """Find the monorepo commit that bumped happy-cli to ``version``.

    Walks the commit history of packages/happy-cli/package.json until the
    blob at that commit reports the matching version. The pnpm-lock.yaml
    at that SHA is what produced the published tarball.
    """
    commits_url = (
        f"https://api.github.com/repos/{MONOREPO}/commits"
        f"?path={CLI_PACKAGE_JSON}&per_page=30"
    )
    commits = cast("list[dict[str, Any]]", fetch_json(commits_url))

    for commit in commits:
        sha = commit["sha"]
        raw_url = (
            f"https://raw.githubusercontent.com/{MONOREPO}/{sha}/{CLI_PACKAGE_JSON}"
        )
        with urllib.request.urlopen(raw_url, timeout=30) as resp:
            pkg = json.loads(resp.read())
        if pkg.get("version") == version:
            return cast("str", sha)

    msg = (
        f"No commit on {MONOREPO}:{CLI_PACKAGE_JSON} declares version {version}. "
        "The release may have been published from a branch not yet merged."
    )
    raise RuntimeError(msg)


def prefetch_github(rev: str) -> str:
    """Prefetch a fetchFromGitHub-compatible tarball and return its SRI hash."""
    url = f"https://github.com/{MONOREPO}/archive/{rev}.tar.gz"
    result = nix_command(
        ["store", "prefetch-file", "--unpack", "--hash-type", "sha256", "--json", url],
    )
    return cast("str", json.loads(result.stdout)["hash"])


def main() -> None:
    """Update the happy-coder package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_npm_version(NPM_PACKAGE)

    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    print("Locating monorepo commit for this release...")
    rev = find_release_commit(latest)
    print(f"  -> {rev[:12]}")

    print("Calculating source hash...")
    src_hash = prefetch_github(rev)

    new_data: dict[str, Any] = {
        "version": latest,
        "srcRev": rev,
        "srcHash": src_hash,
        "pnpmDepsHash": data.get("pnpmDepsHash", ""),
    }

    update_dependency_hash(".#happy-coder", "pnpmDepsHash", HASHES_FILE, new_data)
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
