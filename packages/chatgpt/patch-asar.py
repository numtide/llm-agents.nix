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
from pathlib import Path

# detect-libc's process.report probe trips a CFI guard in the bundled
# Owl/Electron runtime on NixOS and kills the process with SIGILL. With the
# guard false, detect-libc falls back to its ELF/filesystem/ldd probes. Both
# the main process and @parcel/watcher's named worker load this copy.
SKIP_PROCESS_REPORT = (
    re.compile(rb"isLinux\(\) && process\.report"),
    lambda _m: b"false /* nix:skip report */",
)

# The app copies bundled plugins to ~/.codex with fs.cp, which preserves the
# store's read-only modes, and then fails to rewrite manifests there. `exec` is
# the promisified execFile helper from the darwin `ditto` branch; hoisting
# `platform` into a local and GNU `cp -T` stay inside the byte budget. The local
# must not shadow `r` or `n`, which the rest of the function uses.
COPY_PLUGINS_WRITABLE = re.compile(
    rb"(?P<fn>async function [\w$]+\(e,t\)\{)"
    rb'if\("darwin"===(?P<plat>[\w$]+\(\)\.platform)\)'
    rb'(?P<ditto>return void await (?P<exec>[\w$]+)\("/usr/bin/ditto",\["--noqtn",e,t\]\);)'
    rb'if\("win32"!==(?P=plat)\)'
    rb"return void await [\w$]+\(\)\.cp\(e,t,\{recursive:!0,verbatimSymlinks:!0\}\);"
)


def _copy_writable(m: re.Match[bytes]) -> bytes:
    return (
        m["fn"]
        + b"let o="
        + m["plat"]
        + b';if("darwin"===o)'
        + m["ditto"]
        + b'if("win32"!==o)return await '
        + m["exec"]
        + b'("cp",["-rT",e,t]),await '
        + m["exec"]
        + b'("chmod",["-R","u+w",t]);'
    )


# The Local Work executor copies codex-app-tools to executor-plugins with
# fs.cp and then cannot rewrite or re-copy the read-only result. `dirs` is the
# bundle's recursive u+w helper for directories, which lets fs.cp replace a
# tree left read-only by earlier builds. The command path is under cwd, so a
# prefix replace stands in for path.relative, and `+w` for `u+w`, to stay inside
# the byte budget. The replace callback keeps `$` in the destination literal.
COPY_EXECUTOR_PLUGIN_WRITABLE = re.compile(
    rb"(?P<cp>await [\w$]+\(\)\.cp\((?P<server>[\w$]+)\.cwd,(?P<dst>[\w$]+),\{recursive:!0\}\)),"
    rb'"win32"!==process\.platform&&\((?P=server)\.command=(?P<path>[\w$]+\(\))\.join\('
    rb"(?P=dst),(?P=path)\.relative\((?P=server)\.cwd,(?P=server)\.command\)\)\),"
)
MAKE_DIRS_WRITABLE = re.compile(
    rb"async function (?P<dirs>[\w$]+)\(e\)\{let t=await (?P<fs>[\w$]+\(\))\.lstat\(e\)"
    rb'\.catch\(e=>\{if\("ENOENT"===e\.code\)return null;throw e\}\);'
    rb"if\(null==t\|\|!t\.isDirectory\(\)\)return;await (?P=fs)\.chmod\(e,128\|t\.mode\);"
    rb"let r=await (?P=fs)\.readdir\(e,\{withFileTypes:!0\}\);"
    rb"await Promise\.all\(r\.filter\(e=>e\.isDirectory\(\)\)\.map\(t=>(?P=dirs)\("
)


def _find_one(pattern: re.Pattern[bytes], data: bytes) -> re.Match[bytes]:
    matches = list(pattern.finditer(data))
    if len(matches) != 1:
        sys.exit(f"expected 1 match for {pattern.pattern[:60]!r}, got {len(matches)}")
    return matches[0]


def _copy_executor_plugin_writable(m: re.Match[bytes]) -> bytes:
    exec_ = _find_one(COPY_PLUGINS_WRITABLE, m.string)["exec"]
    dirs = _find_one(MAKE_DIRS_WRITABLE, m.string)["dirs"]
    server, dst = m["server"], m["dst"]
    return (
        b"await "
        + dirs
        + b"("
        + dst
        + b"),"
        + m["cp"]
        + b",await "
        + exec_
        + b'("chmod",["-R","+w",'
        + dst
        + b"]),"
        + server
        + b".command="
        + server
        + b".command.replace("
        + server
        + b".cwd,_=>"
        + dst
        + b"),"
    )


PATCHES: list[tuple[re.Pattern[bytes], Callable[[re.Match[bytes]], bytes]]] = [
    SKIP_PROCESS_REPORT,
    # Runs before COPY_PLUGINS_WRITABLE rewrites the function it reads exec from.
    (COPY_EXECUTOR_PLUGIN_WRITABLE, _copy_executor_plugin_writable),
    (COPY_PLUGINS_WRITABLE, _copy_writable),
]


def main() -> None:
    """Patch the asar archive in place."""
    parser = argparse.ArgumentParser()
    parser.add_argument("asar", type=Path)
    args = parser.parse_args()
    asar: Path = args.asar

    data = asar.read_bytes()
    for pattern, build in PATCHES:
        m = _find_one(pattern, data)
        original = m.group(0)
        replacement = build(m)
        if len(replacement) > len(original):
            sys.exit(f"replacement longer than original: {replacement[:60]!r}...")
        data = (
            data[: m.start()] + replacement.ljust(len(original), b" ") + data[m.end() :]
        )
    asar.write_bytes(data)


if __name__ == "__main__":
    main()
