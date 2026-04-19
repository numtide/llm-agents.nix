#!/usr/bin/env python3
"""Discover packages and flake inputs for update checking.

Discovers all packages with version attributes and all flake inputs,
outputting a matrix JSON suitable for GitHub Actions.
"""

import json
import logging
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

from lib import write_output

log = logging.getLogger(__name__)

NIX_EXPR = """
let
  config = builtins.fromJSON (builtins.getEnv "DISCOVERY_CONFIG");
  flake = builtins.getFlake (toString ./.);
  pkgs = flake.packages.${config.system};
  isHidden = pkg: pkg.passthru.hideFromDocs or false;
  getVersion = name:
    if pkgs ? ${name} && pkgs.${name} ? version && !(isHidden pkgs.${name})
    then { inherit name; value = pkgs.${name}.version; }
    else null;
in
  if config.filter == null then
    builtins.mapAttrs (name: pkg:
      if pkg ? version && !(isHidden pkg) then pkg.version else null
    ) pkgs
  else
    builtins.listToAttrs
      (builtins.filter (x: x != null) (map getVersion config.filter))
"""


@dataclass(frozen=True, slots=True)
class MatrixItem:
    """Represents an item in the update matrix."""

    type: str
    name: str
    current_version: str

    def to_dict(self) -> dict[str, str]:
        """Convert to dictionary for JSON serialization."""
        return {
            "type": self.type,
            "name": self.name,
            "current_version": self.current_version,
        }


def discover_packages(
    packages_filter: list[str] | None, system: str
) -> list[MatrixItem]:
    """Discover packages with version attributes in a single nix eval."""
    log.info("Discovering packages...")

    config = json.dumps({"system": system, "filter": packages_filter})
    result = subprocess.run(
        ["nix", "eval", "--json", "--impure", "--expr", NIX_EXPR],
        capture_output=True,
        text=True,
        env={**os.environ, "DISCOVERY_CONFIG": config},
        check=False,
    )
    if result.returncode != 0:
        log.error("Failed to evaluate packages: %s", result.stderr)
        return []

    versions: dict[str, str | None] = json.loads(result.stdout)
    items = [
        MatrixItem(type="package", name=name, current_version=version)
        for name, version in sorted(versions.items())
        if version is not None
    ]

    if packages_filter is None:
        for name, version in sorted(versions.items()):
            if version is None:
                log.info("Skipping %s (no version attribute)", name)
    else:
        found = set(versions.keys())
        for pkg in packages_filter:
            if pkg not in found:
                log.warning("Package %s not found or has no version", pkg)

    return items


def discover_flake_inputs(inputs_filter: list[str] | None) -> list[MatrixItem]:
    """Discover flake inputs from flake.lock."""
    log.info("Discovering flake inputs...")

    lock_path = Path("flake.lock")
    if not lock_path.exists():
        log.info("No flake.lock found, skipping input updates")
        return []

    nodes: dict[str, dict[str, object]] = json.loads(lock_path.read_text()).get(
        "nodes", {}
    )
    input_names = inputs_filter or sorted(k for k in nodes if k != "root")

    items: list[MatrixItem] = []
    for name in input_names:
        node = nodes.get(name)
        if node is None:
            continue
        locked = node.get("locked")
        rev = (
            locked.get("rev", "unknown")[:8] if isinstance(locked, dict) else "unknown"
        )
        items.append(MatrixItem(type="flake-input", name=name, current_version=rev))

    return items


def write_matrix(matrix_items: list[MatrixItem]) -> None:
    """Write matrix JSON and has-updates flag to GITHUB_OUTPUT or log summary."""
    has_updates = len(matrix_items) > 0
    matrix = {"include": [item.to_dict() for item in matrix_items]}
    matrix_json = json.dumps(matrix, separators=(",", ":"))

    write_output("matrix", matrix_json)
    write_output("has-updates", str(has_updates).lower())

    if not os.environ.get("GITHUB_OUTPUT"):
        log.info("")
        log.info("=== Pretty-printed Matrix ===")
        log.info("%s", json.dumps(matrix, indent=2))
        if has_updates:
            type_counts: dict[str, int] = {}
            for item in matrix_items:
                type_counts[item.type] = type_counts.get(item.type, 0) + 1
            log.info("")
            log.info("=== Summary ===")
            for item_type, count in sorted(type_counts.items()):
                log.info("  %d %s", count, item_type)


def main() -> None:
    """Discover packages and flake inputs, output matrix for GitHub Actions."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    packages_env = os.environ.get("PACKAGES", "")
    inputs_env = os.environ.get("INPUTS", "")
    include_inputs = os.environ.get("INCLUDE_INPUTS", "true").lower() == "true"
    system = os.environ.get("SYSTEM", "x86_64-linux")

    log.info("=== Discovery Configuration ===")
    log.info("PACKAGES: %s", packages_env or "<all>")
    log.info("INPUTS: %s", inputs_env or ("<all>" if include_inputs else "<disabled>"))
    log.info("")

    matrix_items = [
        *discover_packages(packages_env.split() or None, system),
        *(discover_flake_inputs(inputs_env.split() or None) if include_inputs else []),
    ]

    log.info("")
    log.info("=== Discovery Results ===")
    if matrix_items:
        log.info("Found %d item(s) to update", len(matrix_items))
    else:
        log.info("No items to update")

    write_matrix(matrix_items)


if __name__ == "__main__":
    main()
