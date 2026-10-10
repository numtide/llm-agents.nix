#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update Prime Agent, its Python components, and Cargo dependencies."""

from __future__ import annotations

import re
import sys
import tarfile
import tempfile
import tomllib
from dataclasses import dataclass
from pathlib import Path
from urllib.request import urlretrieve

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import should_update
from updater.hash import (
    DUMMY_SHA256_HASH,
    calculate_url_hash,
    extract_hash_from_build_error,
)
from updater.nix import NixCommandError, nix_build, nix_eval
from updater.version import fetch_github_latest_release

OWNER = "PrimeIntellect-ai"
REPO = "prime-agent"
PACKAGE_ATTR = ".#prime-agent"
PACKAGE_DIR = Path(__file__).parent
PACKAGE_NIX = PACKAGE_DIR / "package.nix"


@dataclass(frozen=True)
class ReleaseMetadata:
    """Metadata extracted from one immutable upstream release."""

    runtime_version: str
    skill_versions: dict[str, str]


def read_member(
    tar: tarfile.TarFile,
    members: dict[str, tarfile.TarInfo],
    path: str,
) -> bytes:
    """Read one root-relative regular file from a release archive."""
    member = members.get(path)
    if member is None:
        msg = f"Release archive has no {path}"
        raise ValueError(msg)
    extracted = tar.extractfile(member)
    if extracted is None:
        msg = f"Could not extract {path}"
        raise ValueError(msg)
    return extracted.read()


def python_project_version(data: bytes, path: str) -> str:
    """Read a static PEP 621 project version from pyproject.toml."""
    project = tomllib.loads(data.decode()).get("project")
    version = project.get("version") if isinstance(project, dict) else None
    if not isinstance(version, str):
        msg = f"{path} has no static project.version"
        raise TypeError(msg)
    return version


def fetch_release(version: str) -> ReleaseMetadata:
    """Extract Python metadata from one upstream release."""
    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{version}.tar.gz"
    with tempfile.TemporaryDirectory() as tmpdir:
        archive = Path(tmpdir) / "source.tar.gz"
        urlretrieve(url, archive)
        with tarfile.open(archive, "r:gz") as tar:
            members = {
                item.name.split("/", 1)[1]: item
                for item in tar.getmembers()
                if item.isfile() and "/" in item.name
            }
            runtime_path = "prime-agent-runtime/pyproject.toml"
            runtime_version = python_project_version(
                read_member(tar, members, runtime_path), runtime_path
            )
            skill_versions: dict[str, str] = {}
            prefix = "skills/"
            suffix = "/pyproject.toml"
            for path in sorted(members):
                if not path.startswith(prefix) or not path.endswith(suffix):
                    continue
                directory = path.removeprefix(prefix).removesuffix(suffix)
                if "/" in directory:
                    continue
                skill_versions[directory] = python_project_version(
                    read_member(tar, members, path), path
                )

    return ReleaseMetadata(runtime_version, skill_versions)


def replace_once(text: str, pattern: str, replacement: str) -> str:
    """Replace exactly one package.nix field."""
    updated, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        msg = f"Expected one match for {pattern!r}, found {count}"
        raise ValueError(msg)
    return updated


def update_python_versions(text: str, release: ReleaseMetadata) -> str:
    """Update each packaged Python component from its own pyproject.toml."""
    packaged_skills = set(re.findall(r'directory = "([^"]+)";', text))
    upstream_skills = set(release.skill_versions)
    if packaged_skills != upstream_skills:
        added = sorted(upstream_skills - packaged_skills)
        removed = sorted(packaged_skills - upstream_skills)
        msg = f"Bundled Python skills changed: added={added}, removed={removed}"
        raise ValueError(msg)

    updated = replace_once(
        text,
        r'(pname = "prime-agent-runtime";\n\s+version = ")[^"]+(";)',
        rf"\g<1>{release.runtime_version}\g<2>",
    )
    for directory, version in sorted(release.skill_versions.items()):
        updated = replace_once(
            updated,
            rf'(directory = "{re.escape(directory)}";\n\s+version = ")[^"]+(";)',
            rf"\g<1>{version}\g<2>",
        )
    return updated


def main() -> None:
    """Update source, Python versions, and Cargo dependency hash."""
    current = nix_eval(f"{PACKAGE_ATTR}.version")
    latest = fetch_github_latest_release(OWNER, REPO)
    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    original_nix = PACKAGE_NIX.read_text()
    try:
        release = fetch_release(latest)
        source_url = (
            f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
        )
        print("Calculating source hash...")
        source_hash = calculate_url_hash(source_url, unpack=True)

        updated = replace_once(
            original_nix,
            r'(version = ")[^"]+(";)',
            rf"\g<1>{latest}\g<2>",
        )
        updated = replace_once(
            updated,
            r'(tag = "v\$\{finalAttrs\.version\}";\n\s+hash = ")[^"]+(";)',
            rf"\g<1>{source_hash}\g<2>",
        )
        updated = update_python_versions(updated, release)
        updated = replace_once(
            updated,
            r'(cargoHash = ")[^"]+(";)',
            rf"\g<1>{DUMMY_SHA256_HASH}\g<2>",
        )
        PACKAGE_NIX.write_text(updated)

        print("Calculating cargoHash...")
        try:
            nix_build(f"{PACKAGE_ATTR}.unwrapped")
        except NixCommandError as error:
            cargo_hash = extract_hash_from_build_error(str(error))
            if cargo_hash is None:
                msg = "Could not extract cargoHash from Nix build"
                raise ValueError(msg) from error
        else:
            msg = "Build unexpectedly accepted dummy cargoHash"
            raise ValueError(msg)

        PACKAGE_NIX.write_text(
            replace_once(
                PACKAGE_NIX.read_text(),
                r'(cargoHash = ")[^"]+(";)',
                rf"\g<1>{cargo_hash}\g<2>",
            )
        )

        print("Validating updated package...")
        nix_build(PACKAGE_ATTR)
        print(f"Updated to {latest}")
    except Exception:
        PACKAGE_NIX.write_text(original_nix)
        raise


if __name__ == "__main__":
    main()
