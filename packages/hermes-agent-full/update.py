#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for hermes-agent-full.

Tracks the upstream ``NousResearch/hermes-agent`` main branch by pinning the
latest main commit, its unpacked source hash, and the npm dependency hashes
owned by package.nix.
"""

import importlib
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Protocol, cast

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))


JsonObject = dict[str, object]
JsonArray = list[object]


class _FetchJsonFn(Protocol):
    def __call__(self, url: str, *, timeout: int = 30) -> JsonObject | JsonArray: ...


class _FetchTextFn(Protocol):
    def __call__(self, url: str, *, timeout: int = 30) -> str: ...


class _NixBuildFn(Protocol):
    def __call__(
        self,
        attr: str,
        *,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]: ...


class _ExtractHashFn(Protocol):
    def __call__(self, error_output: str) -> str | None: ...


updater = importlib.import_module("updater")
updater_hash = importlib.import_module("updater.hash")
updater_nix = importlib.import_module("updater.nix")

fetch_json = cast("_FetchJsonFn", updater.fetch_json)
fetch_text = cast("_FetchTextFn", updater.fetch_text)
DUMMY_SHA256_HASH = cast("str", updater_hash.DUMMY_SHA256_HASH)
extract_hash_from_build_error = cast(
    "_ExtractHashFn",
    updater_hash.extract_hash_from_build_error,
)
NixCommandError = cast("type[Exception]", updater_nix.NixCommandError)
nix_build = cast("_NixBuildFn", updater_nix.nix_build)

OWNER = "NousResearch"
REPO = "hermes-agent"
PACKAGE_ATTR = ".#hermes-agent-full"
SCRIPT_DIR = Path(__file__).parent
PACKAGE_NIX = SCRIPT_DIR / "package.nix"
RAW_BASE = f"https://raw.githubusercontent.com/{OWNER}/{REPO}"
ARCHIVE_BASE = f"https://github.com/{OWNER}/{REPO}/archive"
MAIN_COMMIT_API = f"https://api.github.com/repos/{OWNER}/{REPO}/commits/main"

FIELD_PATTERNS = {
    "upstreamVersion": r'(^\s*upstreamVersion = ")([^"]+)(";\s*$)',
    "snapshotDate": r'(^\s*snapshotDate = ")([^"]+)(";\s*$)',
    "rev": r'(^\s*rev = ")([0-9a-f]+)(";\s*$)',
    "srcHash": r'(src = fetchFromGitHub \{.*?\n\s*hash = ")([^"]+)(";)',
    "frontendNpmDepsHash": r'(frontend = buildNpmPackage \{.*?\n\s*npmDepsHash = ")([^"]+)(";)',
    "rootNodeModulesNpmDepsHash": r'(rootNodeModules = buildNpmPackage \{.*?\n\s*npmDepsHash = ")([^"]+)(";)',
    "whatsappBridgeNpmDepsHash": r'(whatsappBridge = buildNpmPackage \(_finalAttrs: \{.*?\n\s*npmDepsHash = ")([^"]+)(";)',
}


def read_package_nix() -> str:
    """Return the current package.nix contents."""
    return PACKAGE_NIX.read_text()


def write_package_nix(text: str) -> None:
    """Write updated package.nix contents."""
    _ = PACKAGE_NIX.write_text(text)


def replace_match(match: re.Match[str] | re.Match[bytes], value: str) -> str:
    """Rewrite a regex match while preserving the surrounding syntax."""
    return f"{cast('str', match.group(1))}{value}{cast('str', match.group(3))}"


def replace_field(text: str, field: str, value: str) -> str:
    """Replace one tracked field inside package.nix."""
    pattern = FIELD_PATTERNS[field]
    replaced, count = re.subn(
        pattern,
        lambda match: replace_match(match, value),
        text,
        count=1,
        flags=re.MULTILINE | re.DOTALL,
    )
    if count != 1:
        msg = f"Could not update {field} in {PACKAGE_NIX}"
        raise RuntimeError(msg)
    return replaced


def get_field(text: str, field: str) -> str:
    """Read one tracked field from package.nix."""
    pattern = FIELD_PATTERNS[field]
    match = re.search(pattern, text, flags=re.MULTILINE | re.DOTALL)
    if not match:
        msg = f"Could not read {field} from {PACKAGE_NIX}"
        raise RuntimeError(msg)
    return match.group(2)


def fetch_main_snapshot() -> tuple[str, str]:
    """Return the latest main commit SHA and its YYYY-MM-DD snapshot date."""
    data = fetch_json(MAIN_COMMIT_API)
    if not isinstance(data, dict):
        msg = f"Expected dict from {MAIN_COMMIT_API}, got {type(data).__name__}"
        raise TypeError(msg)
    rev = cast("str", data["sha"])
    commit = cast("JsonObject", data["commit"])
    committer = cast("JsonObject", commit["committer"])
    snapshot_date = cast("str", committer["date"])[:10]
    return rev, snapshot_date


def fetch_upstream_version(rev: str) -> str:
    """Read the upstream base version from pyproject.toml at ``rev``."""
    pyproject_raw = fetch_text(f"{RAW_BASE}/{rev}/pyproject.toml")
    pyproject = tomllib.loads(pyproject_raw)
    project = cast("JsonObject", pyproject["project"])
    return cast("str", project["version"])


def prefetch_source_hash(rev: str) -> str:
    """Prefetch the unpacked GitHub archive hash for ``rev``."""
    prefetch = subprocess.run(
        [
            "nix-prefetch-url",
            "--type",
            "sha256",
            "--unpack",
            f"{ARCHIVE_BASE}/{rev}.tar.gz",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    hash_b32 = prefetch.stdout.strip()

    sri = subprocess.run(
        ["nix", "hash", "to-sri", "--type", "sha256", hash_b32],
        check=True,
        capture_output=True,
        text=True,
    )
    return sri.stdout.strip()


def calculate_package_hash(field: str) -> str:
    """Recompute one npm dependency hash owned by package.nix."""
    package_nix = read_package_nix()
    original = get_field(package_nix, field)
    write_package_nix(replace_field(package_nix, field, DUMMY_SHA256_HASH))

    try:
        _ = nix_build(PACKAGE_ATTR, check=True)
        msg = f"Build unexpectedly succeeded with dummy {field}"
        raise RuntimeError(msg)
    except NixCommandError as err:
        resolved = extract_hash_from_build_error(str(err))
        if not resolved:
            write_package_nix(replace_field(read_package_nix(), field, original))
            raise

    write_package_nix(replace_field(read_package_nix(), field, resolved))
    return resolved


def main() -> None:
    """Update the pinned main snapshot and owned hashes in package.nix."""
    os.chdir(SCRIPT_DIR.parent.parent)

    package_nix = read_package_nix()
    current_rev = get_field(package_nix, "rev")
    rev, snapshot_date = fetch_main_snapshot()

    print(f"Current rev: {current_rev}")
    print(f"Latest rev:  {rev}")

    if rev == current_rev:
        print("Already up to date")
        return

    upstream_version = fetch_upstream_version(rev)
    src_hash = prefetch_source_hash(rev)

    package_nix = replace_field(package_nix, "upstreamVersion", upstream_version)
    package_nix = replace_field(package_nix, "snapshotDate", snapshot_date)
    package_nix = replace_field(package_nix, "rev", rev)
    package_nix = replace_field(package_nix, "srcHash", src_hash)
    write_package_nix(package_nix)

    print(f"upstreamVersion: {upstream_version}")
    print(f"snapshotDate:    {snapshot_date}")
    print(f"src hash:        {src_hash}")

    for field in (
        "frontendNpmDepsHash",
        "rootNodeModulesNpmDepsHash",
        "whatsappBridgeNpmDepsHash",
    ):
        resolved = calculate_package_hash(field)
        print(f"{field}: {resolved}")

    print("Updated hermes-agent-full")


if __name__ == "__main__":
    main()
