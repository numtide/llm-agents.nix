"""Interpolate {name} placeholders in a URL template.

Must match Nix builtins.replaceStrings (lib/interpolate.nix) exactly: build and
updater interpolate the same template, so any divergence means they fetch
different URLs. The interpolate-conformance flake check pins the shared contract.
Semantics (replaceStrings, NOT str.format): single left-to-right pass so a
replacement's output is not re-scanned; unknown placeholders are left as-is.
"""

from __future__ import annotations

import re
from urllib.parse import quote


def interpolate(template: str, variables: dict[str, str]) -> str:
    """Replace ``{name}`` with ``variables[name]`` in one pass."""
    if not variables:
        return template
    pattern = re.compile("|".join(re.escape("{" + name + "}") for name in variables))
    return pattern.sub(lambda m: variables[m.group(0)[1:-1]], template)


def version_vars(version: str) -> dict[str, str]:
    """Template vars derived from a version: ``{version}`` and ``{versionEnc}``.

    ``versionEnc`` is percent-encoded (``+`` -> ``%2B``) for hosts that reject
    reserved characters in the path. Mirrors ``versionVars`` in
    lib/interpolate.nix (lib.strings.escapeURL == quote(safe="")).
    """
    return {"version": version, "versionEnc": quote(version, safe="")}
