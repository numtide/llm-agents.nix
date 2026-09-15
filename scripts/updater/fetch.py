"""Source-identity layer: dispatch a purl to a handler for version/location/hash.

Network and hashing go through :class:`Deps` so version selection and URL
construction stay offline-testable. A purl is an identity, not always a
locator, so the ``x_*`` qualifiers carry tag/url templates and platform maps.
"""

from __future__ import annotations

import json
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from functools import cmp_to_key
from typing import TYPE_CHECKING, Any, ClassVar, Protocol, runtime_checkable

from .hash import calculate_url_hash
from .http import fetch_json, fetch_text
from .interpolate import interpolate, version_vars
from .version import compare_versions, should_update

if TYPE_CHECKING:
    from collections.abc import Callable

    from .purl import Purl

_version_key = cmp_to_key(compare_versions)

# Conservative on purpose: a date-suffixed tag like 2025.11.06-8fe8a63 is NOT a
# prerelease.
_PRERELEASE = re.compile(
    r"(?i)[-.](rc|alpha|beta|pre|preview|dev|nightly|canary|snapshot)"
)


class FetchError(Exception):
    """Base class for all fetcher errors."""


class UnknownPurlTypeError(FetchError):
    """No handler is registered for a purl's type."""


class NoVersionFoundError(FetchError):
    """No discovered version matched the policy."""


class MissingQualifierError(FetchError):
    """A purl lacks a qualifier the handler needs."""

    def __init__(self, key: str, purl: Purl) -> None:
        """Record the missing qualifier key and the purl."""
        msg = f"purl {purl} is missing required qualifier {key!r}"
        super().__init__(msg)


class UnknownPlatformMapError(FetchError):
    """An ``x_platforms`` value names a platform map we don't ship."""


@dataclass(frozen=True)
class Location:
    """One concrete downloadable artifact resolved from a purl."""

    component: str  # "src" or a nix platform like "x86_64-linux"
    url: str
    unpack: bool = False  # hash the unpacked tree (fetchzip) vs the file
    upstream_sha: str | None = None  # hex checksum if upstream publishes one


@dataclass(frozen=True)
class Resolved:
    """A discovered version and the upstream ref it maps to."""

    version: str  # bare version, e.g. "1.2.3"
    ref: str  # upstream tag/ref this maps to, e.g. "rust-v1.2.3"
    extra: dict[str, str] = field(default_factory=dict)  # sub-versions, etc.


@dataclass(frozen=True)
class VersionPolicy:
    """How to pick one version from the candidates a handler discovers.

    ``kind`` is one of ``semver`` (highest), ``prerelease_exclude`` (highest
    stable), ``regex_filter`` (highest matching ``regex``), or
    ``follow_pointer`` (trust the upstream's own "latest" pointer, which may
    move the version *down*).
    """

    kind: str = "semver"
    regex: str | None = None

    def wants_candidate_list(self) -> bool:
        """Whether the handler must fetch all versions, not just "latest"."""
        return self.kind != "semver"

    def _eligible(self, versions: list[str]) -> list[str]:
        """Apply the policy's filter without picking a winner."""
        if self.kind == "regex_filter" and self.regex is not None:
            pattern = self.regex
            return [v for v in versions if re.fullmatch(pattern, v)]
        if self.kind == "prerelease_exclude":
            return [v for v in versions if not _PRERELEASE.search(v)]
        return list(versions)

    def select(self, versions: list[str]) -> str | None:
        """Choose the winning version, or None if nothing is eligible."""
        if self.kind == "follow_pointer":
            return versions[0] if versions else None
        eligible = self._eligible(versions)
        if not eligible:
            return None
        return max(eligible, key=_version_key)

    def should_write(self, current: str, chosen: str) -> bool:
        """Whether ``chosen`` should replace ``current``.

        ``follow_pointer`` allows downgrades (upstream pointer is authoritative);
        every other policy requires a strict increase.
        """
        if self.kind == "follow_pointer":
            return current != chosen
        return should_update(current, chosen)


@dataclass(frozen=True)
class Deps:
    """Injected side-effecting primitives (network, hashing).

    Tests pass fakes so handler logic runs offline; real code uses
    :func:`default_deps`.
    """

    fetch_json: Callable[[str], dict[str, Any] | list[Any]]
    fetch_text: Callable[[str], str]
    hash_url: Callable[..., str]  # (url, *, unpack=False) -> SRI


def default_deps() -> Deps:
    """Wire :class:`Deps` to the real HTTP and hashing helpers."""

    def hash_url(url: str, *, unpack: bool = False) -> str:
        return calculate_url_hash(url, unpack=unpack)

    return Deps(fetch_json=fetch_json, fetch_text=fetch_text, hash_url=hash_url)


@runtime_checkable
class PurlHandler(Protocol):
    """One ecosystem's version discovery, location, and hashing."""

    purl_type: ClassVar[str]

    def latest_version(self, purl: Purl, policy: VersionPolicy) -> Resolved:
        """Discover the latest version for ``purl`` under ``policy``."""
        ...

    def locations(self, purl: Purl, resolved: Resolved) -> list[Location]:
        """Build the concrete download location(s) for a resolved version."""
        ...

    def source_hash(self, loc: Location) -> str:
        """Return the SRI hash for one location."""
        ...


class PurlFetcher:
    """Registry that dispatches purl operations to the right handler."""

    def __init__(self, handlers: list[PurlHandler]) -> None:
        """Index ``handlers`` by their ``purl_type``."""
        self._handlers: dict[str, PurlHandler] = {h.purl_type: h for h in handlers}

    @classmethod
    def default(cls, deps: Deps | None = None) -> PurlFetcher:
        """Build a fetcher with every built-in handler registered."""
        # Lazy: handlers import from this module, so a top-level import is circular.
        from .handlers import (  # noqa: PLC0415
            CargoHandler,
            GenericHandler,
            GiteaHandler,
            GithubHandler,
            NpmHandler,
        )

        resolved_deps = deps or default_deps()
        return cls(
            [
                GithubHandler(resolved_deps),
                NpmHandler(resolved_deps),
                GenericHandler(resolved_deps),
                CargoHandler(resolved_deps),
                GiteaHandler(resolved_deps),
            ]
        )

    def handler(self, purl: Purl) -> PurlHandler:
        """Return the handler for ``purl``'s type, or raise."""
        try:
            return self._handlers[purl.type]
        except KeyError as exc:
            msg = f"no handler for purl type {purl.type!r}"
            raise UnknownPurlTypeError(msg) from exc

    def resolve(self, purl: Purl, policy: VersionPolicy | None = None) -> Resolved:
        """Discover the latest version for ``purl``."""
        return self.handler(purl).latest_version(purl, policy or VersionPolicy())

    def hashes(self, purl: Purl, resolved: Resolved) -> dict[str, str]:
        """Return ``{component: sri}`` for every location of a resolved version.

        Platform matrices are hashed in parallel.
        """
        handler = self.handler(purl)
        locations = handler.locations(purl, resolved)
        if len(locations) <= 1:
            return {loc.component: handler.source_hash(loc) for loc in locations}
        with ThreadPoolExecutor(max_workers=len(locations)) as executor:
            futures = {
                executor.submit(handler.source_hash, loc): loc.component
                for loc in locations
            }
            return {
                futures[future]: future.result() for future in as_completed(futures)
            }


def _platform_vars(value: object) -> dict[str, str]:
    """Normalize one platform-map entry to a var set.

    A bare string is the ``{platform}`` variable; an object is its own set of
    interpolation vars (e.g. ``{"os": "linux", "cpu": "x86_64"}``).
    """
    if isinstance(value, dict):
        return {str(k): str(v) for k, v in value.items()}
    return {"platform": str(value)}


def resolve_platform_map(purl: Purl) -> dict[str, dict[str, str]]:
    """Resolve the ``x_platforms`` qualifier (inline JSON) to nix-platform -> var set."""
    spec = purl.q("x_platforms")
    if not spec:
        return {}
    try:
        parsed = json.loads(spec)
    except (ValueError, TypeError):
        parsed = None
    if not isinstance(parsed, dict):
        msg = f"x_platforms must be a JSON object, got {spec!r}"
        raise UnknownPlatformMapError(msg)
    return {str(k): _platform_vars(v) for k, v in parsed.items()}


def templated_locations(
    purl: Purl, resolved: Resolved, url_template: str
) -> list[Location]:
    """Build locations from a URL template, fanning out over the platform map.

    The template may use ``{version}``, ``{ref}``, ``{platform}`` and any key
    in ``resolved.extra``. No platform map yields a single ``src``.
    """
    unpack = purl.q("x_unpack") == "true"
    fmt: dict[str, str] = {
        **version_vars(resolved.version),
        "ref": resolved.ref,
        **{k: str(v) for k, v in resolved.extra.items()},
    }
    platforms = resolve_platform_map(purl)
    if not platforms:
        return [Location("src", interpolate(url_template, fmt), unpack=unpack)]
    return [
        Location(
            nix_platform, interpolate(url_template, {**fmt, **plat_vars}), unpack=unpack
        )
        for nix_platform, plat_vars in platforms.items()
    ]


def as_dict(data: object) -> dict[str, Any]:
    """Narrow a decoded JSON value to a dict, or raise."""
    if not isinstance(data, dict):
        msg = f"expected a JSON object, got {type(data).__name__}"
        raise TypeError(msg)
    return data


def as_list(data: object) -> list[Any]:
    """Narrow a decoded JSON value to a list, or raise."""
    if not isinstance(data, list):
        msg = f"expected a JSON array, got {type(data).__name__}"
        raise TypeError(msg)
    return data


def apply_tag_template(template: str, version: str) -> str:
    """Turn a bare version into an upstream ref (``v{v}`` -> ``v1.2.3``)."""
    return template.replace("{v}", version)


def strip_tag_template(ref: str, template: str) -> str:
    """Turn an upstream ref back into a bare version (``rust-v1.2.3`` -> ``1.2.3``)."""
    prefix, _, suffix = template.partition("{v}")
    out = ref
    if prefix and out.startswith(prefix):
        out = out[len(prefix) :]
    if suffix and out.endswith(suffix):
        out = out[: len(out) - len(suffix)]
    return out
