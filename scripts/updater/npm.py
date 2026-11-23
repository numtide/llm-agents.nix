"""NPM package utilities for Nix package updates."""

import json
import os
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import quote
from urllib.request import urlretrieve

from updater.http import fetch_json


def _can_prefetch_npm_lockfile(lockfile: Path) -> bool:
    """Return whether Nix can prefetch the lockfile and npm ci accepts it."""
    data: dict[str, Any] = json.loads(lockfile.read_text())
    packages = data.get("packages", {})
    if not isinstance(packages, dict):
        return True

    for package_path, package_data in packages.items():
        if package_path == "" or not isinstance(package_data, dict):
            continue

        # npm ci ignores entries whose parent is not installed and then reports
        # the lockfile as out of sync with package.json.
        parent, separator, _ = package_path.rpartition("/node_modules/")
        if separator and parent not in packages:
            print(f"Skipping npm-shrinkwrap.json; {package_path} has no parent entry")
            return False

        resolved = package_data.get("resolved")
        if not isinstance(resolved, str) or resolved.startswith("git+"):
            continue

        if "integrity" not in package_data:
            print(f"Skipping npm-shrinkwrap.json; missing integrity for {package_path}")
            return False

    return True


def _add_missing_registry_metadata(lockfile: Path) -> None:
    """Fill in resolved/integrity that npm 11 omits for deduplicated entries.

    Without them ``npm ci`` and Nix's npm dependency prefetcher reject the
    lockfile, so query the registry for the missing dist metadata.
    """
    lock: dict[str, Any] = json.loads(lockfile.read_text())
    packages: dict[str, dict[str, Any]] = lock["packages"]

    count = 0
    for path, metadata in packages.items():
        version = metadata.get("version")
        if (
            "node_modules/" not in path
            or not isinstance(version, str)
            or metadata.get("link")
            or metadata.get("inBundle")
            or "integrity" in metadata
        ):
            continue

        name = path.rsplit("node_modules/", 1)[1]
        url = f"https://registry.npmjs.org/{quote(name, safe='')}/{quote(version, safe='')}"
        registry = fetch_json(url)
        if not isinstance(registry, dict) or "dist" not in registry:
            msg = f"Missing npm dist metadata for {name}@{version}"
            raise TypeError(msg)
        dist = registry["dist"]
        metadata.update({"resolved": dist["tarball"], "integrity": dist["integrity"]})
        count += 1

    if count:
        lockfile.write_text(json.dumps(lock, indent=2) + "\n")
        print(f"Added registry metadata to {count} lockfile entries")


def _supplement_missing_optional_deps(lockfile: Path) -> None:
    """Add lock entries for optional dependencies npm omitted.

    npm skips lock entries for optional dependencies of bundled packages
    (e.g. esbuild, tsx), which later makes ``npm ci`` reject the lockfile.
    """
    lock = json.loads(lockfile.read_text())
    packages = lock["packages"]

    present = {
        key.rsplit("node_modules/", 1)[-1] for key in packages if "node_modules/" in key
    }
    missing = {
        name: requirement
        for metadata in packages.values()
        for name, requirement in metadata.get("optionalDependencies", {}).items()
        if name not in present
    }
    if not missing:
        return

    with tempfile.TemporaryDirectory() as tmpdir:
        supplement = Path(tmpdir)
        (supplement / "package.json").write_text(
            json.dumps(
                {
                    "name": "lock-supplement",
                    "version": "1.0.0",
                    "optionalDependencies": missing,
                }
            )
        )
        subprocess.run(
            ["npm", "install", "--package-lock-only", "--ignore-scripts"],
            cwd=supplement,
            check=True,
        )
        extra = json.loads((supplement / "package-lock.json").read_text())

    for key, metadata in extra["packages"].items():
        if key:
            packages.setdefault(key, metadata)

    lockfile.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"Added lock entries for {len(missing)} missing optional dependencies")


def _mispinned_bundled_deps(packages: dict[str, Any]) -> dict[str, dict[str, str]]:
    """Return exact pins of bundled packages that resolve to another version.

    npm writes such a lockfile but ``npm ci`` rejects it as out of sync.
    """
    result: dict[str, dict[str, str]] = {}
    for path, metadata in packages.items():
        if not metadata.get("inBundle"):
            continue
        for name, requirement in metadata.get("dependencies", {}).items():
            if not re.fullmatch(r"\d+\.\d+\.\d+(-[\w.]+)?", requirement):
                continue
            scope = path
            while scope and f"{scope}/node_modules/{name}" not in packages:
                scope = scope.rpartition("/node_modules/")[0]
            found = packages.get(f"{scope}/node_modules/{name}".lstrip("/"), {})
            if found.get("version", requirement) != requirement:
                result.setdefault(path, {})[name] = requirement
    return result


def _supplement_mispinned_bundled_deps(lockfile: Path) -> None:
    """Nest the pinned version below bundled packages that need it."""
    lock = json.loads(lockfile.read_text())
    packages = lock["packages"]

    for path, pins in _mispinned_bundled_deps(packages).items():
        with tempfile.TemporaryDirectory() as tmpdir:
            supplement = Path(tmpdir)
            (supplement / "package.json").write_text(
                json.dumps(
                    {
                        "name": "lock-supplement",
                        "version": "1.0.0",
                        "dependencies": pins,
                    }
                )
            )
            subprocess.run(
                ["npm", "install", "--package-lock-only", "--ignore-scripts"],
                cwd=supplement,
                check=True,
            )
            extra = json.loads((supplement / "package-lock.json").read_text())[
                "packages"
            ]

        for name in pins:
            wanted = [
                name,
                *extra[f"node_modules/{name}"].get("optionalDependencies", {}),
            ]
            for dependency in wanted:
                key = f"node_modules/{dependency}"
                packages[f"{path}/{key}"] = extra[key]
        print(f"Nested {', '.join(pins)} below bundled {path}")

    lockfile.write_text(json.dumps(lock, indent=2) + "\n")


def extract_or_generate_lockfile(
    tarball_url: str,
    output_path: Path,
    *,
    env: dict[str, str] | None = None,
    strip_dev_dependencies: bool = False,
    supplement_optional_deps: bool = False,
) -> bool:
    """Extract an npm lockfile from npm tarball or generate it.

    Downloads the npm tarball, checks if it contains package-lock.json or
    npm-shrinkwrap.json, and either extracts it or generates one using npm.

    Args:
        tarball_url: URL to the npm package tarball
        output_path: Path where package-lock.json should be written
        env: Optional environment variables to pass to npm install
        strip_dev_dependencies: Drop devDependencies from package.json before
            generating the lockfile. Needed for packages published from a
            workspace whose devDependencies use the ``workspace:*`` protocol,
            which npm cannot resolve outside the monorepo. Mirror this with a
            matching ``del(.devDependencies)`` in the package's derivation.
        supplement_optional_deps: Add lock entries npm omits for optional
            dependencies of bundled packages.

    Returns:
        True if lockfile was successfully extracted or generated, False otherwise

    """
    print("Extracting/generating package-lock.json from tarball...")

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        tarball_path = tmpdir_path / "package.tgz"
        urlretrieve(tarball_url, tarball_path)

        with tarfile.open(tarball_path, "r:gz") as tar:
            tar.extractall(tmpdir_path, filter="data")

        package_dir = tmpdir_path / "package"
        package_lock_src = package_dir / "package-lock.json"
        shrinkwrap_src = package_dir / "npm-shrinkwrap.json"

        if package_lock_src.exists():
            output_path.write_text(package_lock_src.read_text())
            print("Updated package-lock.json from tarball")
            return True

        # npm-shrinkwrap.json uses the same lockfile format and is published to
        # npm tarballs. Prefer it over regenerating a less exact lockfile when
        # it has enough metadata for Nix's npm dependency prefetcher.
        if shrinkwrap_src.exists() and _can_prefetch_npm_lockfile(shrinkwrap_src):
            output_path.write_text(shrinkwrap_src.read_text())
            print("Updated package-lock.json from npm-shrinkwrap.json in tarball")
            return True

        print("No npm lockfile in tarball, generating package-lock.json...")
        package_json = package_dir / "package.json"
        if not package_json.exists():
            print("ERROR: No package.json found!")
            return False

        if strip_dev_dependencies:
            manifest = json.loads(package_json.read_text())
            if manifest.pop("devDependencies", None) is not None:
                package_json.write_text(json.dumps(manifest, indent=2) + "\n")
                print("Stripped devDependencies before generating lockfile")

        run_env = {**os.environ, **(env or {})}

        # npm updates npm-shrinkwrap.json instead of creating package-lock.json
        # when shrinkwrap is present. Remove it when falling back to generation.
        if shrinkwrap_src.exists():
            shrinkwrap_src.unlink()

        subprocess.run(
            ["npm", "install", "--package-lock-only", "--ignore-scripts"],
            cwd=package_dir,
            env=run_env,
            check=True,
        )

        new_lock = package_dir / "package-lock.json"
        if new_lock.exists():
            output_path.write_text(new_lock.read_text())
            if supplement_optional_deps:
                _supplement_missing_optional_deps(output_path)
                _supplement_mispinned_bundled_deps(output_path)
            _add_missing_registry_metadata(output_path)
            print("Generated package-lock.json")
            return True

        print("ERROR: Failed to generate package-lock.json")
        return False
