"""Update claude-desktop from Anthropic's APT index and darwin release feed.

Anthropic publish Claude Desktop as prebuilt Debian packages through an APT
repository; there is no source tree and no GitHub releases. This script reads
the per-architecture Packages index, picks the highest version for each arch,
and records the download URLs and SRI hashes in hashes.json. The two arches may
sit at different versions when one lags behind, so each arch is handled on its
own and the top-level version follows x86_64-linux.

macOS builds are distributed through a Squirrel.Mac feed (RELEASES.json) as a
single universal zip covering both darwin arches. That channel is versioned
independently of the APT one, so per-platform versions are recorded in a
"versions" map (package.nix falls back to the top-level "version" for any
platform missing from it).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_json,
    fetch_text,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import hex_to_sri

APT_BASE = "https://downloads.claude.ai/claude-desktop/apt/stable"
DIST_BASE = APT_BASE + "/dists/stable/main"
PLATFORMS = {"x86_64-linux": "amd64", "aarch64-linux": "arm64"}

# The darwin feed publishes one universal artifact for both darwin arches and
# carries no checksums, so the zip must be fetched and hashed here.
DARWIN_FEED = "https://downloads.claude.ai/releases/darwin/universal/RELEASES.json"
DARWIN_PLATFORMS = ("aarch64-darwin",)

HASHES_FILE = Path(__file__).parent / "hashes.json"


def parse_version(version: str) -> tuple[int, ...]:
    """Turn a dotted version into an int tuple for sorting (non-numeric -> 0)."""
    parts = []
    for part in version.split("."):
        try:
            parts.append(int(part))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def latest_for_arch(arch: str) -> tuple[str, str, str]:
    """Return (version, filename, sha256_hex) of the newest release for arch.

    The Packages index holds one RFC822-style stanza per published version,
    separated by blank lines.
    """
    text = fetch_text(f"{DIST_BASE}/binary-{arch}/Packages")

    candidates = []
    for stanza in text.split("\n\n"):
        fields = {}
        for line in stanza.splitlines():
            if ": " in line:
                key, value = line.split(": ", 1)
                fields[key] = value
        version = fields.get("Version")
        filename = fields.get("Filename")
        sha256 = fields.get("SHA256")
        if version and filename and sha256:
            candidates.append((version, filename, sha256))

    if not candidates:
        msg = f"No package stanza found for arch {arch}"
        raise RuntimeError(msg)

    candidates.sort(key=lambda entry: parse_version(entry[0]))
    return candidates[-1]


def latest_darwin() -> tuple[str, str]:
    """Return (version, url) of the newest universal darwin release."""
    feed = fetch_json(DARWIN_FEED)
    if not isinstance(feed, dict):
        msg = "RELEASES.json did not return an object"
        raise TypeError(msg)

    candidates = []
    for release in feed.get("releases", []):
        update_to = release.get("updateTo") or {}
        version = release.get("version") or update_to.get("version", "")
        url = update_to.get("url", "")
        if version and url:
            candidates.append((version, url))

    if not candidates:
        msg = "No darwin release found in RELEASES.json"
        raise RuntimeError(msg)

    candidates.sort(key=lambda entry: parse_version(entry[0]))

    # The feed usually lists a single release, but prefer the declared
    # currentRelease when a history is present.
    current = feed.get("currentRelease", "")
    for version, url in candidates:
        if version == current:
            return version, url
    return candidates[-1]


def main() -> None:
    """Refresh hashes.json when a newer release is available for any channel."""
    current = load_hashes(HASHES_FILE)

    urls = {}
    hashes = {}
    versions = {}
    for platform, arch in PLATFORMS.items():
        version, filename, sha256_hex = latest_for_arch(arch)
        versions[platform] = version
        urls[platform] = f"{APT_BASE}/{filename}"
        hashes[platform] = hex_to_sri(sha256_hex)

    darwin_version, darwin_url = latest_darwin()

    # The darwin artifact is a ~370 MB download; reuse the recorded hash while
    # the URL is unchanged.
    recorded_url = current.get("urls", {}).get("aarch64-darwin")
    if recorded_url == darwin_url:
        darwin_hash = current["hashes"]["aarch64-darwin"]
    else:
        darwin_hash = calculate_url_hash(darwin_url)
    for platform in DARWIN_PLATFORMS:
        versions[platform] = darwin_version
        urls[platform] = darwin_url
        hashes[platform] = darwin_hash

    new_version = versions["x86_64-linux"]

    # Also catch an arm64-only bump while amd64 stays put, or a darwin-only
    # bump while the APT channel stays put.
    changed = (
        should_update(current.get("version", ""), new_version)
        or urls != current.get("urls", {})
        or hashes != current.get("hashes", {})
        or versions != current.get("versions", {})
    )

    if not changed:
        print("claude-desktop: already up to date")
        return

    save_hashes(
        HASHES_FILE,
        {
            "version": new_version,
            "versions": versions,
            "urls": urls,
            "hashes": hashes,
        },
    )
    print(f"Updated to {new_version} (darwin: {darwin_version})")


if __name__ == "__main__":
    main()
