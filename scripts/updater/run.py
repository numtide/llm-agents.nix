"""Execute a package's declarative ``passthru.updater`` config.

Turns the JSON config CI hands us back into flow arguments and delegates to the
tested flow functions, so declarative packages and legacy ``update.py`` scripts
share one code path.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Callable
from functools import cmp_to_key
from pathlib import Path
from typing import Any

from .flows import (
    update_bun_github,
    update_github_source,
    update_manifest_binaries,
    update_manifest_checksums,
    update_npm_package,
    update_platform_binaries,
)
from .purl import Purl
from .version import (
    compare_versions,
    fetch_github_latest_release,
    fetch_npm_version,
    fetch_version_from_text,
)

# Injectable so run() is testable without network/Nix.
FlowMap = dict[str, Callable[..., None]]

_DEFAULT_FLOWS: FlowMap = {
    "github-source": update_github_source,
    "npm": update_npm_package,
    "bun-github": update_bun_github,
    "platform": update_platform_binaries,
    "manifest": update_manifest_binaries,
    "manifest-checksums": update_manifest_checksums,
}


def _owner(purl: Purl) -> str:
    """Return the purl's namespace (repo owner), or raise if absent."""
    if purl.namespace is None:
        msg = f"purl {purl} needs an owner (namespace)"
        raise ValueError(msg)
    return purl.namespace


def _latest_git_tag(url: str) -> str:
    """Highest version among a Gitea/Forgejo tags API list (v-prefix stripped)."""
    from .http import fetch_json  # noqa: PLC0415 -- keep http import lazy

    tags = fetch_json(url)
    if not isinstance(tags, list):
        msg = f"expected a list of tags from {url}"
        raise TypeError(msg)
    versions = [str(tag["name"]).removeprefix("v") for tag in tags]
    if not versions:
        msg = f"no tags found at {url}"
        raise ValueError(msg)
    return max(versions, key=cmp_to_key(compare_versions))


def _version_getter(source: dict[str, Any]) -> Callable[[], str]:
    """Build the ``fetch_latest`` callable for a versionSource type."""
    from .http import fetch_text  # noqa: PLC0415 -- keep http import lazy

    source_type = source["type"]
    if source_type == "github":
        return lambda: fetch_github_latest_release(source["owner"], source["repo"])
    if source_type == "npm":
        package = source["package"]
        tag = source.get("tag", "latest")
        return lambda: fetch_npm_version(package, tag=tag)
    if source_type == "text":
        url = source["url"]
        regex = source.get("regex")
        if regex:
            return lambda: fetch_version_from_text(url, regex)
        return lambda: fetch_text(url).strip()
    if source_type == "git-tags":
        url = source["url"]
        return lambda: _latest_git_tag(url)
    msg = f"unknown versionSource type {source_type!r}"
    raise ValueError(msg)


def run(pkg_dir: Path, config: dict[str, Any], *, flows: FlowMap | None = None) -> None:
    """Execute one declarative updater config against ``pkg_dir``."""
    flow = flows if flows is not None else _DEFAULT_FLOWS
    kind = config["kind"]

    if kind == "github-source":
        purl = Purl.parse(config["purl"])
        flow["github-source"](
            pkg_dir,
            _owner(purl),
            purl.name,
            config["flakeAttr"],
            config["depHashKey"],
        )
    elif kind == "bun-github":
        purl = Purl.parse(config["purl"])
        flow["bun-github"](
            pkg_dir,
            _owner(purl),
            purl.name,
            ref_prefix=config.get("refPrefix", "v"),
        )
    elif kind == "npm":
        purl = Purl.parse(config["purl"])
        package = f"{purl.namespace}/{purl.name}" if purl.namespace else purl.name
        flow["npm"](
            pkg_dir,
            package,
            config["flakeAttr"],
            dist_tag=purl.q("x_dist_tag"),
            fetchzip=config.get("fetchzip", False),
            require_lockfile=config.get("requireLockfile", True),
            strip_dev_dependencies=config.get("stripDevDependencies", False),
            supplement_optional_deps=config.get("supplementOptionalDeps", False),
            lockfile_env=config.get("lockfileEnv"),
        )
    elif kind == "platform":
        flow["platform"](
            pkg_dir,
            fetch_latest=_version_getter(config["versionSource"]),
            url_template=config["urlTemplate"],
            platforms=config["platforms"],
        )
    elif kind == "manifest":
        platform_map = {
            (entry["os"], entry["arch"]): entry["platform"]
            for entry in config["platformMap"]
        }
        flow["manifest"](
            pkg_dir,
            manifest_url=config["manifestUrl"],
            platform_map=platform_map,
        )
    elif kind == "manifest-checksums":
        flow["manifest-checksums"](
            pkg_dir,
            fetch_latest=_version_getter(config["versionSource"]),
            manifest_url_template=config["manifestUrl"],
            checksum_path=config["checksumPath"],
            platforms=config["platforms"],
            allow_downgrade=config.get("versionPolicy") == "follow_pointer",
        )
    else:
        msg = f"unknown updater kind {kind!r}"
        raise ValueError(msg)


def main(argv: list[str] | None = None) -> None:
    """CLI entry: ``python3 -m updater.run --pkg-dir DIR --config JSON``."""
    parser = argparse.ArgumentParser(description="Run a passthru.updater config.")
    parser.add_argument("--pkg-dir", required=True, type=Path)
    parser.add_argument("--config", required=True, help="updater config as JSON")
    args = parser.parse_args(argv)

    pkg_dir: Path = args.pkg_dir
    config_json: str = args.config
    config: dict[str, Any] = json.loads(config_json)
    run(pkg_dir, config)


if __name__ == "__main__":
    main()
