#!/usr/bin/env python3
"""Perform updates for packages or flake inputs.

Outputs (written to GITHUB_OUTPUT):
  updated: "true" or "false"
  new_version: the new version string
  changelog: the changelog URL (packages only)
"""

import argparse
import json
import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path

from updater.version import compare_versions

from lib import UpdateType, nix_eval_raw, run, write_output

log = logging.getLogger(__name__)


def sandbox_works(bwrap: str) -> bool:
    """Probe whether bubblewrap can create its namespaces here."""
    probe = [bwrap, "--ro-bind", "/", "/", "--", "true"]
    if run(probe, check=False, capture=True).returncode == 0:
        return True
    # Ubuntu 24.04 runners restrict unprivileged user namespaces via
    # AppArmor. The runner user has passwordless sudo, so lift the limit.
    if shutil.which("sudo"):
        run(
            ["sudo", "sysctl", "-w", "kernel.apparmor_restrict_unprivileged_userns=0"],
            check=False,
            capture=True,
        )
    return run(probe, check=False, capture=True).returncode == 0


def sandbox_wrap(cmd: list[str], name: str) -> list[str]:
    """Confine updater code with bubblewrap.

    The filesystem is read-only except the package's own directory, /nix,
    and a fresh tmpfs HOME and /tmp. Network stays available for upstream
    APIs. Set UPDATE_SANDBOX=0 to opt out locally.
    """
    if sys.platform != "linux" or os.environ.get("UPDATE_SANDBOX") == "0":
        return cmd
    bwrap = shutil.which("bwrap")
    if bwrap is None:
        log.warning("::warning::bwrap not found; running updater unsandboxed")
        return cmd
    if not sandbox_works(bwrap):
        log.warning(
            "::warning::bubblewrap cannot create namespaces; "
            "running updater unsandboxed"
        )
        return cmd
    pkg_dir = str(Path.cwd() / "packages" / name)
    # Fresh HOME instead of a tmpfs over the real one, which would hide
    # ~/.nix-profile/bin. Later binds override the read-only root.
    return [
        bwrap,
        *("--ro-bind", "/", "/"),
        *("--dev", "/dev"),
        *("--proc", "/proc"),
        *("--tmpfs", "/tmp"),  # noqa: S108 — sandbox mount, not a host temp path
        *("--dir", "/tmp/home"),  # noqa: S108
        *("--setenv", "HOME", "/tmp/home"),  # noqa: S108
        *("--setenv", "TMPDIR", "/tmp"),  # noqa: S108
        # /run/user/<uid> is read-only in here; dotnet's fetch-deps needs it.
        *("--unsetenv", "XDG_RUNTIME_DIR"),
        *("--bind", "/nix", "/nix"),
        *("--bind", pkg_dir, pkg_dir),
        *("--chdir", str(Path.cwd())),
        "--die-with-parent",
        "--",
        *cmd,
    ]


def git_has_changes() -> bool:
    """Check if the branch differs from origin/main.

    Diffing against origin/main also catches commits already on a reused
    update/* branch that never made it into a pull request.
    """
    return run(["git", "diff", "--quiet", "origin/main"], check=False).returncode != 0


def run_update_command(cmd: list[str], error_label: str) -> None:
    """Run an update command, streaming merged stdout+stderr, and exit on failure."""
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.returncode != 0:
        log.error("::error::%s", error_label)
        sys.exit(1)


def load_companions(name: str) -> list[str]:
    """Load companion package names from packages/<name>/update-companions.

    Companions must be bumped in the same commit as the primary package,
    e.g. because they assert matching versions at build time.
    """
    companions_file = Path(f"packages/{name}/update-companions")
    if not companions_file.exists():
        return []
    return [
        stripped
        for line in companions_file.read_text().splitlines()
        if (stripped := line.strip()) and not stripped.startswith("#")
    ]


def has_declarative_updater(name: str) -> bool:
    """Whether the package carries a declarative passthru.updater config.

    Such packages expose a standard passthru.updateScript (attached in
    flake.nix from the config), so the update is one ``nix run`` away.
    """
    result = run(
        [
            "nix",
            "eval",
            f".#packages.x86_64-linux.{name}.updater",
            "--apply",
            "_: true",
        ],
        check=False,
        capture=True,
    )
    return result.returncode == 0 and result.stdout.strip() == "true"


def load_nix_update_args(name: str) -> list[str]:
    """Load extra nix-update arguments from the package's nix-update-args file."""
    args_file = Path(f"packages/{name}/nix-update-args")
    if not args_file.exists():
        return []
    log.info("Loading nix-update args from %s", args_file)
    return [
        stripped
        for line in args_file.read_text().splitlines()
        if (stripped := line.strip()) and not stripped.startswith("#")
    ]


def run_package_updater(name: str) -> None:
    """Run one package's updater: its updateScript, or nix-update."""
    log.info("Updating package %s...", name)

    if has_declarative_updater(name):
        log.info("Running updateScript for %s...", name)
        run_update_command(
            sandbox_wrap(
                ["nix", "run", f".#packages.x86_64-linux.{name}.updateScript"], name
            ),
            f"updateScript failed for package {name}",
        )
    else:
        log.info("No update script found, trying nix-update...")
        run_update_command(
            sandbox_wrap(
                ["nix-update", "--flake", name, *load_nix_update_args(name)], name
            ),
            f"nix-update failed for package {name}",
        )


def refuse_downgrade(name: str, old_version: str, new_version: str) -> None:
    """Exit if an updater moved the package backwards.

    nix-update takes the highest version its source lists, even if that is older
    than the packaged one. GitHub's release list has omitted recent releases.
    """
    if compare_versions(new_version, old_version) < 0:
        log.error(
            "::error::Refusing to downgrade %s from %s to %s",
            name,
            old_version,
            new_version,
        )
        sys.exit(1)


def update_package(name: str) -> None:
    """Update a package and its companions."""
    attr = f".#packages.x86_64-linux.{name}"
    old_version = nix_eval_raw(f"{attr}.version") or "unknown"

    run_package_updater(name)
    for companion in load_companions(name):
        run_package_updater(companion)

    if not git_has_changes():
        log.info("No changes detected")
        write_output("updated", "false")
        return

    new_version = nix_eval_raw(f"{attr}.version") or "unknown"
    log.info("New version: %s", new_version)
    # A follow_pointer package tracks upstream's pointer down as well.
    if nix_eval_raw(f"{attr}.updater.versionPolicy") != "follow_pointer":
        refuse_downgrade(name, old_version, new_version)

    changelog = nix_eval_raw(f"{attr}.meta.changelog") or ""
    if not changelog:
        log.warning("::warning::Package %s is missing meta.changelog", name)

    write_output("updated", "true")
    write_output("new_version", new_version)
    write_output("changelog", changelog)


def update_flake_input(name: str) -> None:
    """Update a single flake input."""
    log.info("Updating input %s...", name)

    if run(["nix", "flake", "update", name], check=False).returncode != 0:
        log.error("::error::Failed to update %s", name)
        sys.exit(1)

    if not git_has_changes():
        log.info("No changes detected")
        write_output("updated", "false")
        return

    metadata_result = run(
        ["nix", "flake", "metadata", "--json", "--no-write-lock-file"],
        capture=True,
    )
    metadata = json.loads(metadata_result.stdout)
    rev: str = (
        metadata.get("locks", {})
        .get("nodes", {})
        .get(name, {})
        .get("locked", {})
        .get("rev", "unknown")
    )
    new_rev = rev[:8]
    log.info("New revision: %s", new_rev)

    write_output("updated", "true")
    write_output("new_version", new_rev)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "type", choices=[t.value for t in UpdateType], help="update type"
    )
    parser.add_argument("name", help="package or flake input name")
    return parser.parse_args()


def main() -> None:
    """Entry point: dispatch to package or flake-input updater."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = parse_args()
    os.environ["NIX_PATH"] = "nixpkgs=flake:nixpkgs"

    match UpdateType(args.type):
        case UpdateType.PACKAGE:
            update_package(args.name)
        case UpdateType.FLAKE_INPUT:
            update_flake_input(args.name)


if __name__ == "__main__":
    main()
