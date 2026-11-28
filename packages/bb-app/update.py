# Copyright (c) 2026 Numtide

"""Update script for the bb-app package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import update_npm_package

update_npm_package(
    Path(__file__).parent,
    "bb-app",
    ".#bb-app",
    # Published from a workspace whose devDependencies use workspace:*.
    strip_dev_dependencies=True,
)
