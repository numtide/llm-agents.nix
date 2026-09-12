#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nodejs --command python3

"""Update script for dsh package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import update_npm_package

update_npm_package(
    Path(__file__).parent,
    "@deepseek-ai/dsh",
    ".#dsh",
    # The tarball ships no lockfile, so npm has to resolve the tree itself.
    # devDependencies name @deepseek-ai/dsh-experimental-code-runtime-python,
    # which upstream never published; without this the resolve aborts with
    # E404 and the update never lands. Mirror in package.nix.
    strip_dev_dependencies=True,
)
