"""Reduce a Cargo workspace to what decides how its dependencies compile.

The result only changes when the dependency graph, features or profiles
change, so dependencies built from it can be reused across releases.
"""

import sys
import tomllib
from pathlib import Path
from typing import Any

import tomli_w

DEP_TABLES = ("dependencies", "dev-dependencies", "build-dependencies")
PLACEHOLDER = "0.0.0"


def dep_tables(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    """Return every table of a manifest that lists dependencies."""
    scopes = [manifest, manifest.get("workspace", {})]
    scopes += manifest.get("target", {}).values()
    tables = [scope[name] for scope in scopes for name in DEP_TABLES if name in scope]
    return tables + list(manifest.get("patch", {}).values())


def normalize_lock(text: str) -> str:
    """Give workspace members a fixed version: releases bump only that."""
    lock = tomllib.loads(text)
    local = {
        f"{p['name']} {p['version']}" for p in lock["package"] if "source" not in p
    }
    for package in lock["package"]:
        if "source" not in package:
            package["version"] = PLACEHOLDER
        package["dependencies"] = [
            f"{dep.split()[0]} {PLACEHOLDER}" if dep in local else dep
            for dep in package.get("dependencies", [])
        ]
        if not package["dependencies"]:
            del package["dependencies"]
    return tomli_w.dumps(lock)


def write_stub(path: Path, content: str) -> None:
    """Write `content` to `path`, creating its directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def stub_package(src: Path, dst: Path, manifest: dict[str, Any]) -> None:
    """Replace the sources of a package with empty targets."""
    package = manifest["package"]
    if isinstance(package.get("version"), str):
        package["version"] = PLACEHOLDER
    package.pop("metadata", None)
    # Tests, examples and benches do not decide how dependencies compile.
    for kind in ("example", "test", "bench"):
        manifest.pop(kind, None)
        package[f"auto{kind}s" if kind != "bench" else "autobenches"] = False

    build = package.get("build", (src / "build.rs").exists())
    if build:
        write_stub(dst / ("build.rs" if build is True else build), "fn main() {}\n")

    bins = [Path(b["path"]) for b in manifest.get("bin", []) if "path" in b]
    bins += [Path("src/bin") / f"{b['name']}.rs" for b in manifest.get("bin", [])]
    if package.get("autobins", True):
        found = [src / "src/main.rs", *src.glob("src/bin/*.rs")]
        found += src.glob("src/bin/*/main.rs")
        bins += [path.relative_to(src) for path in found]
    for path in bins:
        if (src / path).exists():
            write_stub(dst / path, "fn main() {}\n")

    # Always provide a library so that the package has a target left.
    write_stub(dst / manifest.get("lib", {}).get("path", "src/lib.rs"), "")


def stub_manifest(src: Path, dst: Path) -> list[Path]:
    """Write the reduced manifest and return the local crates it refers to."""
    manifest = tomllib.loads((src / "Cargo.toml").read_text())
    manifest.pop("lints", None)
    workspace = manifest.get("workspace", {})
    workspace.pop("lints", None)
    workspace.pop("metadata", None)
    if isinstance(workspace.get("package", {}).get("version"), str):
        workspace["package"]["version"] = PLACEHOLDER

    local = []
    for table in dep_tables(manifest):
        for dep in table.values():
            if isinstance(dep, dict) and "path" in dep:
                # The requirement would not match the placeholder version.
                dep.pop("version", None)
                local.append(src / dep["path"])
    for pattern in workspace.get("members", []):
        local += src.glob(pattern)

    if "package" in manifest:
        stub_package(src, dst, manifest)
    dst.mkdir(parents=True, exist_ok=True)
    (dst / "Cargo.toml").write_text(tomli_w.dumps(manifest))
    return local


def skeleton(top: Path, root: Path, out: Path) -> None:
    """Stub every crate reachable from `root`, keeping paths relative to `top`."""
    names = []
    seen = set()
    todo = [root]
    while todo:
        src = todo.pop().resolve()
        if src in seen or not (src / "Cargo.toml").exists():
            continue
        seen.add(src)
        dst = out / src.relative_to(top)
        todo += stub_manifest(src, dst)
        manifest = tomllib.loads((dst / "Cargo.toml").read_text())
        if "package" in manifest:
            names.append(manifest["package"]["name"])

    dst = out / root.relative_to(top)
    lock = normalize_lock((root / "Cargo.lock").read_text())
    (dst / "Cargo.lock").write_text(lock)
    for config in (".cargo/config.toml", ".cargo/config"):
        if (root / config).exists():
            write_stub(dst / config, (root / config).read_text())
    (out / "members").write_text("".join(f"{name}\n" for name in sorted(names)))


def main() -> None:
    """Run the subcommand given on the command line."""
    match sys.argv[1:]:
        case ["lock", path]:
            sys.stdout.write(normalize_lock(Path(path).read_text()))
        case ["skeleton", top, out]:
            skeleton(Path(top).resolve(), Path.cwd(), Path(out))
        case _:
            sys.exit("usage: cargo-skeleton lock FILE | skeleton TOP OUT")


if __name__ == "__main__":
    main()
