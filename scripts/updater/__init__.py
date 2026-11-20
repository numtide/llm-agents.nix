"""Nix package updater library.

This library provides utilities for updating Nix packages in flakes,
including version fetching, hash calculation, and file modification.
"""

# Bun package utilities
from .bun import (
    clone_and_generate_bun_nix,
    regenerate_bun_nix,
)

# Dependency hash calculation
from .deps import DepHasher, update_dependency_hash

# Purl fetcher (source-identity layer)
from .fetch import (
    Deps,
    Location,
    PurlFetcher,
    Resolved,
    VersionPolicy,
    default_deps,
)

# High-level update flows
from .flows import (
    update_bun_github,
    update_github_source,
    update_manifest_binaries,
    update_npm_package,
    update_platform_binaries,
)

# Hash utilities
from .hash import calculate_url_hash

# Hashes file I/O
from .hashes_file import load_hashes, save_hashes

# HTTP utilities
from .http import fetch_json, fetch_text

# Nix commands
from .nix import (
    NixCommandError,
    nix_build,
    nix_eval,
)

# NPM utilities
from .npm import extract_or_generate_lockfile

# Platform utilities
from .platforms import calculate_platform_hashes

# Purl parsing
from .purl import Purl

# State stores
from .store import HashesJsonStore, StateStore

# Version fetching
from .version import (
    fetch_github_latest_release,
    fetch_npm_version,
    fetch_version_from_text,
    should_update,
)

__all__ = [
    "DepHasher",
    "Deps",
    "HashesJsonStore",
    "Location",
    "NixCommandError",
    "Purl",
    "PurlFetcher",
    "Resolved",
    "StateStore",
    "VersionPolicy",
    "calculate_platform_hashes",
    "calculate_url_hash",
    "clone_and_generate_bun_nix",
    "default_deps",
    "extract_or_generate_lockfile",
    "fetch_github_latest_release",
    "fetch_json",
    "fetch_npm_version",
    "fetch_text",
    "fetch_version_from_text",
    "load_hashes",
    "nix_build",
    "nix_eval",
    "regenerate_bun_nix",
    "save_hashes",
    "should_update",
    "update_bun_github",
    "update_dependency_hash",
    "update_github_source",
    "update_manifest_binaries",
    "update_npm_package",
    "update_platform_binaries",
]
