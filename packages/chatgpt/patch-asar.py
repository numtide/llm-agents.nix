#!/usr/bin/env python3
"""Apply byte-length-preserving source patches inside app.asar.

The asar header records file offsets, so every replacement is padded with
spaces to the original's exact byte length instead of re-packing the archive.
Minified identifiers change between releases, so patterns are regexes that
capture the identifiers they need instead of hard-coding them.
"""

import argparse
import re
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Patch:
    """Replace the single match of `pattern` in place."""

    pattern: re.Pattern[bytes]
    replace: Callable[[re.Match[bytes]], bytes]


# The app copies bundled plugins to ~/.codex with fs.cp, which preserves the
# store's read-only modes, and then fails to rewrite manifests there. `exec` is
# the promisified execFile helper from the darwin `ditto` branch; hoisting
# `platform` into a local buys the bytes to stay inside the byte budget.
def _copy_writable(m: re.Match[bytes]) -> bytes:
    return (
        m["fn"]
        + b"let r="
        + m["plat"]
        + b";if(r===`darwin`)"
        + m["ditto"]
        + b"if(r!==`win32`){await "
        + m["exec"]
        + b"(`cp`,[`-r`,e+`/.`,t]);await "
        + m["exec"]
        + b"(`chmod`,[`-R`,`u+w`,t]);return}"
    )


PATCHES = [
    # detect-libc's process.report probe trips a CFI guard in the bundled
    # Owl/Electron runtime and kills the process with SIGILL. Make its
    # `isLinux() && process.report` guard false so detect-libc falls back to
    # its ELF/filesystem/ldd probes. First the source copy in @parcel/watcher's
    # worker ...
    Patch(
        re.compile(rb"isLinux\(\) && process\.report"),
        lambda _m: b"isLinux() && false",
    ),
    # ... then the minified copy in the main process, loaded by LaTeX previews.
    Patch(
        re.compile(rb"if\([\w$]+\(\)&&process\.report\)\{let"),
        lambda _m: b"if(false){let",
    ),
    Patch(
        re.compile(
            rb"(?P<fn>async function [\w$]+\(e,t\)\{)"
            rb"if\((?P<plat>[\w$]+\.default\.platform)===`darwin`\)"
            rb"(?P<ditto>\{await (?P<exec>[\w$]+)\(`/usr/bin/ditto`,\[`--noqtn`,e,t\]\);return\})"
            rb"if\((?P=plat)!==`win32`\)\{"
            rb"await [\w$]+\.default\.cp\(e,t,\{recursive:!0,verbatimSymlinks:!0\}\);return\}"
        ),
        _copy_writable,
    ),
]


def main() -> None:
    """Patch the asar archive in place."""
    parser = argparse.ArgumentParser()
    parser.add_argument("asar", type=Path)
    args = parser.parse_args()
    asar: Path = args.asar

    data = asar.read_bytes()
    for patch in PATCHES:
        matches = list(patch.pattern.finditer(data))
        if len(matches) != 1:
            sys.exit(
                f"expected 1 match for {patch.pattern.pattern[:60]!r} in {asar}, got {len(matches)}"
            )
        m = matches[0]
        original = m.group(0)
        replacement = patch.replace(m)
        if len(replacement) > len(original):
            sys.exit(f"replacement longer than original: {replacement[:60]!r}...")
        data = (
            data[: m.start()] + replacement.ljust(len(original), b" ") + data[m.end() :]
        )
    asar.write_bytes(data)


if __name__ == "__main__":
    main()
