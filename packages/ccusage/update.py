"""Update script for ccusage.

nix-update handles version, source hash and cargoHash on its own, but it knows
nothing about the LiteLLM pricing snapshot the build embeds. build.rs derives
that snapshot's URL from nodes.litellm.locked in the tagged tree's flake.lock;
we pin a copy instead so the build needs no network. Nothing ties the two
together, so a plain nix-update bump leaves the pin behind and the binary
embeds prices upstream never shipped -- new models silently fall out of the
embedded table.

Re-read the rev from the tag being packaged, then delegate the rest to
nix-update.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_text,
    nix_eval,
    should_update,
)

PACKAGE_NIX = Path(__file__).parent / "package.nix"

OWNER = "ccusage"
REPO = "ccusage"

PRICING_FILE = "model_prices_and_context_window.json"
LOCKED_URL_REV_RE = re.compile(rf"/BerriAI/litellm/([0-9a-f]{{40}})/{PRICING_FILE}$")

# `litellmRev = "<40 hex>";`
LITELLM_REV_RE = re.compile(r'(litellmRev = ")[0-9a-f]{40}(")')
# The first `hash = "..."` inside the litellm-pricing fetchurl block. Anchoring
# on the block keeps this off the fetchFromGitHub hash further down the file.
PRICING_HASH_RE = re.compile(
    r'(litellm-pricing = fetchurl \{.*?hash = ")[^"]+(")',
    re.DOTALL,
)


def resolve_litellm_rev(version: str) -> str:
    """Read the litellm rev that the given ccusage tag builds against.

    Args:
        version: ccusage version without the leading "v".

    Returns:
        The 40-character litellm commit rev from the tag's flake.lock.

    Raises:
        ValueError: If the tag's flake.lock has no litellm rev.

    """
    url = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/v{version}/flake.lock"
    lock = json.loads(fetch_text(url))

    locked = lock.get("nodes", {}).get("litellm", {}).get("locked", {})
    # Since 20.1 the input is a file URL with the rev in its path.
    match = LOCKED_URL_REV_RE.search(locked.get("url", ""))
    rev = locked.get("rev") or (match and match.group(1))
    if not rev:
        msg = f"v{version} flake.lock has no litellm rev"
        raise ValueError(msg)
    return str(rev)


def pinned_litellm_rev() -> str:
    """Read the litellm rev currently pinned in package.nix.

    Returns:
        The pinned 40-character rev.

    Raises:
        ValueError: If package.nix has no litellmRev pin.

    """
    match = LITELLM_REV_RE.search(PACKAGE_NIX.read_text())
    if match is None:
        msg = "package.nix has no litellmRev pin"
        raise ValueError(msg)
    return match.group(0).split('"')[1]


def pin_litellm_pricing(rev: str, pricing_hash: str) -> None:
    """Rewrite the pinned litellm rev and its snapshot hash in package.nix.

    Args:
        rev: litellm commit rev to pin.
        pricing_hash: SRI hash of the pricing JSON at that rev.

    Raises:
        ValueError: If either pin could not be located in package.nix.

    """
    text = PACKAGE_NIX.read_text()

    text, rev_count = LITELLM_REV_RE.subn(rf"\g<1>{rev}\g<2>", text)
    if rev_count != 1:
        msg = f"expected one litellmRev pin in package.nix, found {rev_count}"
        raise ValueError(msg)

    text, hash_count = PRICING_HASH_RE.subn(rf"\g<1>{pricing_hash}\g<2>", text)
    if hash_count != 1:
        msg = f"expected one litellm-pricing hash in package.nix, found {hash_count}"
        raise ValueError(msg)

    PACKAGE_NIX.write_text(text)


def main() -> None:
    """Update ccusage, keeping the LiteLLM pricing pin in step with the tag."""
    current = nix_eval(".#ccusage.version")
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    bump = should_update(current, latest)

    # Re-pin against the version we will actually ship, whether or not there is
    # a new release. The pin can be stale while the version is current -- that
    # is how it drifted two months behind upstream -- so this must not hinge on
    # a bump. Resolve over the network before touching package.nix so an
    # unreachable tag cannot leave a half-written file.
    target = latest if bump else current
    rev = resolve_litellm_rev(target)

    if rev == pinned_litellm_rev():
        print(f"litellm pin already matches v{target} ({rev})")
    else:
        print(f"v{target} pins litellm {rev}, re-pinning")
        pricing_url = (
            f"https://raw.githubusercontent.com/BerriAI/litellm/{rev}/{PRICING_FILE}"
        )
        pricing_hash = calculate_url_hash(pricing_url)
        pin_litellm_pricing(rev, pricing_hash)

    if not bump:
        print("Version already up to date")
        return

    subprocess.run(
        ["nix-update", "--flake", "ccusage", "--version", latest],
        check=True,
    )

    print(f"Updated ccusage to {latest}")


if __name__ == "__main__":
    main()
