"""Update autolith and re-vendor its upstream nix/package.nix."""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_text,
    should_update,
)
from updater.nix import run_command

PACKAGE_DIR = Path(__file__).parent
HASHES = PACKAGE_DIR / "hashes.json"
UPSTREAM_NIX = PACKAGE_DIR / "upstream-package.nix"
OWNER = "lambda-symbolics"
REPO = "autolith"


def vendor_upstream_nix(tag: str) -> str:
    """Fetch upstream's package.nix and strip the parts that need IFD.

    Upstream reads the fff commit and an exact SBCL version/hash pin from
    files inside `src`; inline the former and drop the latter so we can
    follow nixpkgs' SBCL.
    """
    base = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{tag}"
    text = fetch_text(f"{base}/nix/package.nix")
    fff_commit = fetch_text(f"{base}/native/fff/commit").strip()

    text = re.sub(
        r"^  fffSourceCommit = .*$",
        f'  fffSourceCommit = "{fff_commit}";',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    # sbclSource: drop the hash comparison block, keep the extraction.
    text = re.sub(
        r"\n    actual_hash=.*?\n    fi\n", "\n", text, count=1, flags=re.DOTALL
    )
    text = re.sub(
        r"^.*expectedSbcl(Version|SourceHash) = .*\n", "", text, flags=re.MULTILINE
    )
    text = re.sub(
        r"^assert pkgs\.sbcl\.version == expectedSbclVersion;\n",
        "",
        text,
        flags=re.MULTILINE,
    )
    text = text.replace("${expectedSbclVersion}", "${pkgs.sbcl.version}")
    text = re.sub(r"\bstdenv\.is(Linux|Darwin)\b", r"stdenv.hostPlatform.is\1", text)
    if "expectedSbcl" in text:
        msg = "upstream package.nix changed shape; adjust vendor_upstream_nix()"
        raise ValueError(msg)
    return text


def main() -> None:
    """Update to the latest tagged release."""
    data = json.loads(HASHES.read_text())
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)
    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    tag = f"v{latest}"
    upstream = vendor_upstream_nix(tag)
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/{tag}.tar.gz",
        unpack=True,
    )
    UPSTREAM_NIX.write_text(upstream)
    # Keep the vendored file in treefmt's style so updates show real diffs only.
    run_command(["nix", "fmt", "--", str(UPSTREAM_NIX)], cwd=PACKAGE_DIR.parent.parent)
    HASHES.write_text(
        json.dumps({"version": latest, "hash": src_hash}, indent=2) + "\n"
    )
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
