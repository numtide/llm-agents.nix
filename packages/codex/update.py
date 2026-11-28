"""Update script for codex package.

This script updates both the codex version and the librusty_v8 hashes.
The v8 version is extracted from the Cargo.lock file of the codex repository.
"""

import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_platform_hashes,
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_version_from_text,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"

RUSTY_V8_PLATFORMS = {
    "x86_64-linux": "x86_64-unknown-linux-gnu",
    "aarch64-linux": "aarch64-unknown-linux-gnu",
    "aarch64-darwin": "aarch64-apple-darwin",
}


def fetch_version() -> str:
    """Fetch latest codex version from GitHub releases."""
    tag = fetch_github_latest_release("openai", "codex")
    match = re.match(r"^rust-v(.+)$", tag)
    if not match:
        msg = f"Unexpected tag format: {tag!r}, expected 'rust-v<version>'"
        raise ValueError(msg)
    return match.group(1)


def librusty_v8_pins(
    codex_version: str, previous: dict[str, Any] | None
) -> dict[str, Any]:
    """Return the librusty_v8 pin for the given codex version.

    Re-uses existing hashes when the v8 version has not changed to avoid
    re-downloading four ~100MB archives on every bump.
    """
    v8_version = fetch_version_from_text(
        f"https://raw.githubusercontent.com/openai/codex/rust-v{codex_version}/codex-rs/Cargo.lock",
        r'name = "v8"\nversion = "([^"]+)"',
    )
    print(f"V8 version: {v8_version}")

    if previous and previous.get("version") == v8_version:
        print("V8 unchanged, reusing hashes")
        return previous

    # denoland publishes no prebuilts for the v8_enable_sandbox combo codex
    # uses; openai releases their own under the rusty-v8-v<version> tag.
    # Mirrors .github/actions/setup-rusty-v8 in the codex repo.
    profile = "ptrcomp_sandbox_release"
    base_url = (
        f"https://github.com/openai/codex/releases/download/rusty-v8-v{v8_version}"
    )
    hashes = calculate_platform_hashes(
        base_url + "/librusty_v8_" + profile + "_{platform}.a.gz",
        RUSTY_V8_PLATFORMS,
    )
    binding_hashes = calculate_platform_hashes(
        base_url + "/src_binding_" + profile + "_{platform}.rs",
        RUSTY_V8_PLATFORMS,
    )
    return {
        "version": v8_version,
        "profile": profile,
        "baseUrl": base_url,
        "hashes": {k: hashes[k] for k in RUSTY_V8_PLATFORMS},
        "srcBindingHashes": {k: binding_hashes[k] for k in RUSTY_V8_PLATFORMS},
    }


def main() -> None:
    """Update the codex package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_version()

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    tag = f"rust-v{latest}"
    url = f"https://github.com/openai/codex/archive/refs/tags/{tag}.tar.gz"

    print("Calculating source hash...")
    source_hash = calculate_url_hash(url, unpack=True)

    data = {
        "version": latest,
        "hash": source_hash,
        "cargoHash": DUMMY_SHA256_HASH,
        "librusty_v8": librusty_v8_pins(latest, data.get("librusty_v8")),
    }
    save_hashes(HASHES_FILE, data)

    update_dependency_hash(".#codex", "cargoHash", HASHES_FILE, data)

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
