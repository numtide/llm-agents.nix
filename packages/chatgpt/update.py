#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#gnupg nixpkgs#python3 --command python3
"""Update ChatGPT and its primary runtime from OpenAI's distribution servers."""

import hashlib
import json
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import load_hashes, save_hashes, should_update
from updater.hash import hex_to_sri

PACKAGE_DIR = Path(__file__).parent
HASHES_FILE = PACKAGE_DIR / "hashes.json"
KEY_FILE = PACKAGE_DIR / "openai-archive-key.asc"
KEY_FINGERPRINT = "3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"
REPO_BASE = "https://persistent.oaistatic.com/codex-app-prod/linux/deb"
INRELEASE_PATH = "dists/stable/InRelease"
PLATFORMS = {
    "aarch64-linux": "arm64",
    "x86_64-linux": "amd64",
}
RUNTIME_MANIFESTS = {
    "x86_64-linux": (
        "https://persistent.oaistatic.com/"
        "codex-primary-runtime/latest/linux-x64/LATEST.json"
    ),
}
USER_AGENT = (
    "llm-agents.nix package updater (+https://github.com/numtide/llm-agents.nix)"
)


def fetch_url(url: str) -> bytes:
    """Fetch one OpenAI URL."""
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request) as response:
        return bytes(response.read())


def fetch(path: str) -> bytes:
    """Fetch one path from OpenAI's Debian repository."""
    return fetch_url(f"{REPO_BASE}/{path}")


def verify_inrelease(inrelease: bytes) -> str:
    """Verify InRelease with the pinned OpenAI key and return its payload."""
    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)
        inrelease_file = temporary / "InRelease"
        release_file = temporary / "Release"
        keyring_file = temporary / "openai-archive-key.gpg"
        inrelease_file.write_bytes(inrelease)

        subprocess.run(
            [
                "gpg",
                "--batch",
                "--dearmor",
                "--output",
                str(keyring_file),
                str(KEY_FILE),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        verification = subprocess.run(
            [
                "gpgv",
                "--keyring",
                str(keyring_file),
                "--status-fd",
                "1",
                "--output",
                str(release_file),
                str(inrelease_file),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if verification.returncode != 0:
            msg = f"OpenAI InRelease signature verification failed:\n{verification.stderr}"
            raise RuntimeError(msg)

        valid_fingerprints = {
            fields[2]
            for line in verification.stdout.splitlines()
            if (fields := line.split())[:2] == ["[GNUPG:]", "VALIDSIG"]
        }
        if KEY_FINGERPRINT not in valid_fingerprints:
            msg = "OpenAI InRelease was not signed by the pinned key"
            raise RuntimeError(msg)

        return release_file.read_text()


def release_sha256(release: str, wanted_path: str) -> tuple[str, int]:
    """Read the signed SHA256 and size for one repository index."""
    in_sha256 = False
    for line in release.splitlines():
        if line == "SHA256:":
            in_sha256 = True
            continue
        if in_sha256 and not line.startswith(" "):
            break
        if in_sha256:
            digest, size, path = line.split()
            if path == wanted_path:
                return digest, int(size)

    msg = f"{wanted_path} missing from signed InRelease SHA256 section"
    raise ValueError(msg)


def verify_index(index: bytes, expected_hash: str, expected_size: int) -> None:
    """Verify a Packages index against its signed Release metadata."""
    if len(index) != expected_size:
        msg = f"Packages size mismatch: expected {expected_size}, got {len(index)}"
        raise ValueError(msg)
    actual_hash = hashlib.sha256(index).hexdigest()
    if actual_hash != expected_hash:
        msg = f"Packages SHA256 mismatch: expected {expected_hash}, got {actual_hash}"
        raise ValueError(msg)


def parse_packages(packages: str) -> list[dict[str, str]]:
    """Parse Debian control paragraphs from a Packages index."""
    records: list[dict[str, str]] = []
    for paragraph in packages.strip().split("\n\n"):
        record: dict[str, str] = {}
        for line in paragraph.splitlines():
            if line.startswith((" ", "\t")):
                continue
            key, separator, value = line.partition(":")
            if separator:
                record[key] = value.strip()
        records.append(record)
    return records


def source_from_index(platform: str, architecture: str, release: str) -> dict[str, str]:
    """Return one platform source authenticated by the signed APT indexes."""
    index_path = f"main/binary-{architecture}/Packages"
    expected_hash, expected_size = release_sha256(release, index_path)
    packages = fetch(f"dists/stable/{index_path}")
    verify_index(packages, expected_hash, expected_size)

    record = next(
        (
            candidate
            for candidate in parse_packages(packages.decode())
            if candidate.get("Package") == "chatgpt"
            and candidate.get("Architecture") == architecture
        ),
        None,
    )
    if record is None:
        msg = f"chatgpt ({architecture}) missing from {index_path}"
        raise ValueError(msg)

    required_fields = ("Version", "Filename", "SHA256")
    missing_fields = [field for field in required_fields if field not in record]
    if missing_fields:
        msg = f"chatgpt ({architecture}) missing fields: {', '.join(missing_fields)}"
        raise ValueError(msg)

    filename = record["Filename"]
    if not filename.startswith("pool/") or ".." in Path(filename).parts:
        msg = f"unsafe package filename in signed index: {filename}"
        raise ValueError(msg)

    if len(bytes.fromhex(record["SHA256"])) != hashlib.sha256().digest_size:
        msg = f"invalid package SHA256 in signed index for {platform}"
        raise ValueError(msg)

    return {
        "version": record["Version"],
        "url": f"{REPO_BASE}/{filename}",
        "hash": hex_to_sri(record["SHA256"]),
    }


def runtime_source(platform: str, manifest_url: str) -> dict[str, str]:
    """Return the primary runtime source described by OpenAI's latest manifest."""
    manifest = json.loads(fetch_url(manifest_url))
    required_fields = (
        "archiveSha256",
        "archiveUrl",
        "bundleVersion",
        "format",
        "nodeVersion",
        "pythonVersion",
        "runtimeRootDirectoryName",
        "targetArch",
        "targetPlatform",
    )
    missing_fields = [field for field in required_fields if field not in manifest]
    if missing_fields:
        msg = (
            f"primary runtime ({platform}) missing fields: {', '.join(missing_fields)}"
        )
        raise ValueError(msg)

    expected_architecture = {"x86_64-linux": "x64"}[platform]
    if (
        manifest["targetPlatform"] != "linux"
        or manifest["targetArch"] != expected_architecture
    ):
        msg = (
            f"primary runtime ({platform}) target mismatch: "
            f"{manifest['targetPlatform']}-{manifest['targetArch']}"
        )
        raise ValueError(msg)
    if manifest["runtimeRootDirectoryName"] != "codex-primary-runtime":
        msg = f"unexpected primary runtime root for {platform}"
        raise ValueError(msg)
    if manifest["format"] != "tar.xz":
        msg = f"unexpected primary runtime format for {platform}: {manifest['format']}"
        raise ValueError(msg)

    archive_url = manifest["archiveUrl"]
    parsed_url = urllib.parse.urlparse(archive_url)
    if (
        parsed_url.scheme != "https"
        or parsed_url.hostname != "persistent.oaistatic.com"
    ):
        msg = f"unsafe primary runtime URL for {platform}: {archive_url}"
        raise ValueError(msg)

    archive_hash = manifest["archiveSha256"]
    if len(bytes.fromhex(archive_hash)) != hashlib.sha256().digest_size:
        msg = f"invalid primary runtime SHA256 for {platform}"
        raise ValueError(msg)

    return {
        "version": manifest["bundleVersion"],
        "pythonVersion": manifest["pythonVersion"],
        "nodeVersion": manifest["nodeVersion"],
        "url": archive_url,
        "hash": hex_to_sri(archive_hash),
    }


def main() -> None:
    """Refresh the desktop package and primary runtime sources."""
    release = verify_inrelease(fetch(INRELEASE_PATH))
    sources = {
        platform: source_from_index(platform, architecture, release)
        for platform, architecture in PLATFORMS.items()
    }
    runtime_sources = {
        platform: runtime_source(platform, manifest_url)
        for platform, manifest_url in RUNTIME_MANIFESTS.items()
    }

    versions = {source["version"] for source in sources.values()}
    if len(versions) != 1:
        msg = f"OpenAI architecture versions differ: {sorted(versions)}"
        raise ValueError(msg)

    current = load_hashes(HASHES_FILE)
    current_sources = current.get("sources", {})
    for platform, source in sources.items():
        current_version = current_sources.get(platform, {}).get("version", "")
        if (
            current_version
            and source["version"] != current_version
            and not should_update(current_version, source["version"])
        ):
            msg = (
                f"refusing to downgrade {platform} from {current_version} "
                f"to {source['version']}"
            )
            raise ValueError(msg)

    current_runtime_sources = current.get("runtimeSources", {})
    for platform, source in runtime_sources.items():
        current_version = current_runtime_sources.get(platform, {}).get("version", "")
        if (
            current_version
            and source["version"] != current_version
            and not should_update(current_version, source["version"])
        ):
            msg = (
                f"refusing to downgrade {platform} primary runtime from "
                f"{current_version} to {source['version']}"
            )
            raise ValueError(msg)

    if current_sources == sources and current_runtime_sources == runtime_sources:
        print("chatgpt: already up to date")
        return

    save_hashes(
        HASHES_FILE,
        {
            "sources": sources,
            "runtimeSources": runtime_sources,
        },
    )
    print(
        f"chatgpt: updated to {versions.pop()} "
        f"(primary runtime {runtime_sources['x86_64-linux']['version']})"
    )


if __name__ == "__main__":
    main()
