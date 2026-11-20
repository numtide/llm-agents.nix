"""Bun package utilities for Nix package updates.

Provides helpers for regenerating bun.nix lockfiles using bun2nix,
used by packages that depend on the bun2nix flake input.
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from .nix import run_command


def regenerate_bun_nix(
    bun_lock_path: Path,
    bun_nix_output: Path,
    flake_root: Path,
) -> None:
    """Regenerate a bun.nix file from a bun.lock using bun2nix.

    Runs the flake's own ``bun2nix`` package, which is available from the
    binary cache.

    Args:
        bun_lock_path: Path to the bun.lock file
        bun_nix_output: Path where bun.nix should be written
        flake_root: Root directory of the flake (provides the bun2nix package)

    Raises:
        RuntimeError: If bun2nix fails

    """
    try:
        run_command(
            [
                "nix",
                "run",
                f"{flake_root}#bun2nix",
                "--",
                "--lock-file",
                str(bun_lock_path),
                "--output-file",
                str(bun_nix_output),
            ],
            cwd=flake_root,
        )
        # Run the project formatter (deadnix + nixfmt) to strip unused
        # imports and normalise style so CI doesn't fail.
        print(f"Formatting {bun_nix_output.name}...")
        run_command(
            ["nix", "fmt", "--", str(bun_nix_output)],
            cwd=flake_root,
        )
        print(f"Regenerated {bun_nix_output.name}")
    except Exception as e:
        msg = f"bun2nix failed: {e}"
        raise RuntimeError(msg) from e


def clone_and_generate_bun_nix(
    owner: str,
    repo: str,
    version: str,
    bun_nix_output: Path,
    flake_root: Path,
    *,
    ref_prefix: str = "",
    pkg_dir: Path | None = None,
) -> None:
    """Clone a repo at a given version and regenerate bun.nix from its bun.lock.

    This is the high-level helper most update.py scripts should use.
    It handles cloning the repo, locating the bun.lock, and running bun2nix.

    Always runs ``bun install`` to ensure bun.lock is consistent with
    package.json (upstream lockfiles are sometimes stale).

    When the upstream lockfile is stale and ``pkg_dir`` is provided, a patch
    file ``fix-stale-bun-lock.patch`` is written into ``pkg_dir`` so that the
    Nix build can apply it at build time.  When the lockfile is fresh, any
    existing patch file in ``pkg_dir`` is removed so it does not break future
    builds.

    Args:
        owner: GitHub repository owner
        repo: GitHub repository name
        version: Version tag or commit to check out
        bun_nix_output: Path where bun.nix should be written
        flake_root: Root directory of the flake
        ref_prefix: Prefix for the git ref (e.g. "v" for "v1.0.0" tags)
        pkg_dir: Package directory; when set, stale-lockfile patches are
            written here automatically instead of raising an error.

    """
    ref = f"{ref_prefix}{version}"

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_dir = Path(tmpdir) / repo

        print(f"Cloning {owner}/{repo} at {ref}...")
        subprocess.run(
            [
                "git",
                "clone",
                "--depth=1",
                f"--branch={ref}",
                f"https://github.com/{owner}/{repo}.git",
                str(repo_dir),
            ],
            check=True,
            capture_output=True,
        )

        bun_lock = repo_dir / "bun.lock"
        lockfile_was_stale = False

        if not bun_lock.exists():
            # No lockfile shipped — generate one from scratch.
            print("No bun.lock found, generating lockfile...")
            subprocess.run(
                ["bun", "install", "--lockfile-only"],
                cwd=repo_dir,
                check=True,
                capture_output=True,
            )
        else:
            # Verify the shipped lockfile is consistent with package.json.
            # If it's stale, the Nix build will fail because bun tries to
            # resolve the mismatched deps from the network inside the sandbox.
            result = subprocess.run(
                ["bun", "install", "--frozen-lockfile", "--lockfile-only"],
                cwd=repo_dir,
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                lockfile_was_stale = True
                print(
                    "⚠️  Upstream bun.lock is out of sync with package.json, "
                    "refreshing..."
                )
                subprocess.run(
                    ["bun", "install", "--lockfile-only"],
                    cwd=repo_dir,
                    check=True,
                    capture_output=True,
                )

        if not bun_lock.exists():
            msg = f"Could not find or generate bun.lock in {owner}/{repo}"
            raise FileNotFoundError(msg)

        regenerate_bun_nix(bun_lock, bun_nix_output, flake_root)

        patch_file = pkg_dir / "fix-stale-bun-lock.patch" if pkg_dir else None

        if lockfile_was_stale:
            if patch_file is not None:
                # Generate the diff and save it so the Nix build can apply it.
                diff_result = run_command(["git", "diff", "bun.lock"], cwd=repo_dir)
                patch_file.write_text(diff_result.stdout)
                print(
                    f"⚠️  Upstream bun.lock was stale — wrote patch to {patch_file.name}"
                )
            else:
                msg = (
                    f"Upstream {owner}/{repo} {ref} has a stale bun.lock "
                    f"that does not match package.json.\n"
                    f"bun.nix was regenerated from the refreshed lockfile, "
                    f"but the Nix build will still use the stale in-tree "
                    f"bun.lock from the source tarball.\n"
                    f"You need to add a patch that fixes bun.lock at build "
                    f"time.\n"
                    f"\n"
                    f"To generate the patch:\n"
                    f"  git clone --depth=1 --branch={ref} "
                    f"https://github.com/{owner}/{repo}.git /tmp/{repo}\n"
                    f"  cd /tmp/{repo}\n"
                    f"  bun install --lockfile-only\n"
                    f"  git diff bun.lock > fix-stale-bun-lock.patch\n"
                )
                raise RuntimeError(msg)
        elif patch_file is not None:
            # Upstream lockfile is now fresh — clear the patch so it's a no-op.
            patch_file.write_text("")
