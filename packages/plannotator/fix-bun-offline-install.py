# ruff: noqa: INP001
"""Patch plannotator's workspace manifests for offline Bun installs.

Bun's offline install still asks the registry for a handful of workspace
package dependency manifests, even when bun.lock and bun2nix's cache contain
the resolved tarballs.  Move those dependencies to the root workspace at their
locked versions and remove the duplicate workspace manifest entries so the
sandboxed install can resolve everything from the vendored cache.
"""

import json
import re
from pathlib import Path

DEP_SECTIONS = [
    "dependencies",
    "devDependencies",
    "optionalDependencies",
    "peerDependencies",
]

# Runtime dependencies needed by the workspaces we build.  Hoisting them to the
# root workspace lets Bun resolve them directly from the bun2nix cache.
HOISTED = {
    "@joplin/turndown-plugin-gfm",
    "@modelcontextprotocol/client",
    "@modelcontextprotocol/server",
    "@pierre/diffs",
    "@plannotator/webtui",
    "chokidar",
    "jsonc-parser",
    "parse5",
    "turndown",
    "typescript",
    "uqr",
    "zod",
}

# Dependencies of tests and of workspaces that are not built for this package.
# Removing them avoids needless offline manifest lookups.
UNUSED = {
    "@opencode-ai/plugin",
    "@opencode/plugin",
    "fast-check",
    "glimpseui",
}


def locked_versions(lock: str) -> dict[str, str]:
    """Return package versions resolved in bun.lock."""
    resolved = {}
    for match in re.finditer(r'^    "([^"]+)": \["([^"]+)"', lock, re.MULTILINE):
        name, ref = match.groups()
        prefix = f"{name}@"
        if ref.startswith(prefix):
            version = ref[len(prefix) :]
            if not version.startswith("workspace:"):
                resolved[name] = version
    return resolved


def _hoist_deps(data: dict, resolved: dict[str, str]) -> bool:
    deps = data.setdefault("dependencies", {})
    hoisted = sorted(HOISTED & resolved.keys())
    for name in hoisted:
        deps[name] = resolved[name]
    return bool(hoisted)


def _remove_deps(data: dict, names: set[str]) -> bool:
    changed = False
    for section in DEP_SECTIONS:
        deps = data.get(section)
        if not isinstance(deps, dict):
            continue
        for name in sorted(names):
            if name in deps:
                del deps[name]
                changed = True
    return changed


def _exactify_ranges(data: dict, resolved: dict[str, str]) -> bool:
    changed = False
    # patch_lockfile exactifies every range in bun.lock, overrides included.
    for section in [*DEP_SECTIONS, "overrides"]:
        deps = data.get(section)
        if not isinstance(deps, dict):
            continue
        for name, spec in list(deps.items()):
            if (
                isinstance(spec, str)
                and spec.startswith(("^", "~"))
                and name in resolved
            ):
                deps[name] = resolved[name]
                changed = True
    return changed


def patch_package_json_files(resolved: dict[str, str]) -> None:
    """Hoist/remove problematic deps and exactify range specs."""
    for package_json in Path().glob("**/package.json"):
        if "node_modules" in package_json.parts:
            continue

        data = json.loads(package_json.read_text())
        changed = _remove_deps(data, HOISTED | UNUSED)
        if package_json == Path("package.json"):
            changed = _hoist_deps(data, resolved) or changed
        changed = _exactify_ranges(data, resolved) or changed

        if changed:
            package_json.write_text(json.dumps(data, indent=2) + "\n")


def _replace_range(match: re.Match[str], resolved: dict[str, str]) -> str:
    name = match.group(1)
    quote = match.group(2)
    return f'"{name}": {quote}{resolved[name]}{quote}'


def patch_lockfile(lock: str, resolved: dict[str, str]) -> str:
    """Keep bun.lock in sync with the manifest rewrites."""
    names = "|".join(
        re.escape(name) for name in sorted(resolved, key=len, reverse=True)
    )
    if names:
        lock = re.sub(
            rf'"({names})": (["\'])[\^~][^"\']+\2',
            lambda match: _replace_range(match, resolved),
            lock,
        )

    removed_names = "|".join(
        re.escape(name) for name in sorted(HOISTED | UNUSED, key=len, reverse=True)
    )
    if removed_names:
        lock = re.sub(
            rf'^        "({removed_names})": "[^"]+",\n',
            "",
            lock,
            flags=re.MULTILINE,
        )

    root_workspace = lock.index('  "": {')
    root_deps_start = lock.index('    "dependencies": {', root_workspace)
    root_deps_end = lock.index("    },", root_deps_start)
    root_deps_block = lock[root_deps_start:root_deps_end]

    additions = ""
    for name in sorted(HOISTED):
        if name in resolved and f'"{name}":' not in root_deps_block:
            additions += f'        "{name}": "{resolved[name]}",\n'
    if additions:
        lock = lock[:root_deps_end] + additions + lock[root_deps_end:]

    return lock


def main() -> None:
    """Patch package.json files and bun.lock in the current source tree."""
    lock_path = Path("bun.lock")
    lock = lock_path.read_text()
    resolved = locked_versions(lock)

    patch_package_json_files(resolved)
    lock_path.write_text(patch_lockfile(lock, resolved))


if __name__ == "__main__":
    main()
