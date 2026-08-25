#!/usr/bin/env python3
"""Apply byte-length-preserving source patches inside app.asar.

The asar header records file offsets, so every replacement is padded with
spaces to the original's exact byte length instead of re-packing the archive.
"""

import re
import sys
from pathlib import Path

# @parcel/watcher uses detect-libc in a named worker. Its process.report
# fallback trips a CFI guard in the bundled Owl/Electron runtime on NixOS.
# detect-libc falls back to its ELF/filesystem/ldd probes instead.
SKIP_PROCESS_REPORT = (
    b"isLinux() && process.report",
    b"false /* nix:skip report */",
)

# The app materializes bundled plugins in ~/.codex and rewrites selected
# manifests there. Node's fs.cp preserves the Nix store's read-only modes,
# so copy with coreutils and make only the user-owned destination writable.
COPY_PLUGINS_WRITABLE = (
    b'async function Kne(e,t){if(S.default.platform===`darwin`){await Cne(`/usr/bin/ditto`,[`--noqtn`,e,t]);return}if(S.default.platform!==`win32`){await y.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0});return}let{copyDirectoryAllowDecryptedDestinationOnEncryptionFailure:n}=await Promise.resolve().then(()=>require("./windows-file-copy-Bw9CB6bJ.js"));await n({copy:()=>y.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0}),destination:t,source:e})}',
    b'async function Kne(e,t){let r=S.default.platform;if(r===`darwin`){await Cne(`/usr/bin/ditto`,[`--noqtn`,e,t]);return}if(r!==`win32`){await Cne(`cp`,[`-r`,e+`/.`,t]);await Cne(`chmod`,[`-R`,`u+w`,t]);return}let{copyDirectoryAllowDecryptedDestinationOnEncryptionFailure:n}=await Promise.resolve().then(()=>require("./windows-file-copy-Bw9CB6bJ.js"));await n({copy:()=>y.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0}),destination:t,source:e})}',
)

# Resolve the immutable primary runtime facade directly. The compact fallbacks
# preserve the normal Linux cache location when the opt-in wrapper variable is
# absent; Windows-only framework-path handling is irrelevant to this package.
PRIMARY_RUNTIME_ROOTS = (
    (
        b"function FR(e){return e==null&&IL!=null?IL:i.default.join(e??i.default.join(r.default.homedir(),`.cache`,`codex-runtimes`),jL)}",
        b"function FR(e){return process.env.CODEX_PRIMARY_RUNTIME_PATH||(e||r.default.homedir()+`/.cache/codex-runtimes`)+`/`+jL}",
    ),
    (
        b"function jY(e){return e==null&&DY!=null?DY:E.default.join(e??E.default.join(T.default.homedir(),`.cache`,`codex-runtimes`),EY)}",
        b"function jY(e){return process.env.CODEX_PRIMARY_RUNTIME_PATH||(e||T.default.homedir()+`/.cache/codex-runtimes`)+`/`+EY}",
    ),
)

PRIMARY_RUNTIME_STATUS = re.compile(
    rb"async function iR\(.*?(?=async function aR\()",
    re.DOTALL,
)

PRIMARY_RUNTIME_INSTALL = re.compile(
    rb"async function sR\(.*?(?=async function cR\()",
    re.DOTALL,
)

PRIMARY_RUNTIME_STATUS_WRAPPER = (
    b"async function iR(e){let t=process.env.CODEX_PRIMARY_RUNTIME_PATH;"
    b"if(t){let e=(await NR(t))?.bundleVersion??null;return{desiredBundleVersion:e,"
    b"installedBundleVersion:e,status:e?`current`:`missing`}}return iR0(e)}"
)

PRIMARY_RUNTIME_INSTALL_WRAPPER = (
    b"async function sR(e,t,n=`latest`,r={}){let i=process.env."
    b"CODEX_PRIMARY_RUNTIME_PATH;if(i){let t=await HR(i);return{bundleVersion:"
    b"t.bundleVersion??null,paths:await BR({bundleFormatVersion:"
    b"t.bundleFormatVersion??1,runtimeRoot:i,targetPlatform:yR(e.platform)}),"
    b"status:`already-current`}}return cR(e,t,n,r)}"
)


def replace_exact(
    data: bytes, original: bytes, replacement: bytes, label: str
) -> bytes:
    """Replace one exact pattern without changing the archive length."""
    count = data.count(original)
    if count != 1:
        sys.exit(f"expected one {label} pattern, found {count}")
    if len(replacement) > len(original):
        sys.exit(f"replacement longer than original for {label}")
    return data.replace(original, replacement.ljust(len(original), b" "))


def replace_regex(
    data: bytes,
    pattern: re.Pattern[bytes],
    replacement: bytes,
    label: str,
) -> bytes:
    """Replace one regex match without changing the archive length."""
    matches = list(pattern.finditer(data))
    if len(matches) != 1:
        sys.exit(f"expected one {label} function, found {len(matches)}")
    match = matches[0]
    if len(replacement) > len(match.group()):
        sys.exit(f"replacement longer than original for {label}")
    padded = replacement.ljust(len(match.group()), b" ")
    return data[: match.start()] + padded + data[match.end() :]


def main() -> None:
    """Patch the asar archive given as the only argument."""
    asar = Path(sys.argv[1])
    data = asar.read_bytes()
    for original, replacement in (SKIP_PROCESS_REPORT, COPY_PLUGINS_WRITABLE):
        data = replace_exact(data, original, replacement, repr(original[:40]))

    for original, replacement in PRIMARY_RUNTIME_ROOTS:
        data = replace_exact(data, original, replacement, "primary-runtime root")

    status_match = PRIMARY_RUNTIME_STATUS.search(data)
    if status_match is None:
        sys.exit("primary-runtime status function not found")
    renamed_status = (
        status_match.group()
        .replace(b"async function iR(", b"async function iR0(", 1)
        .replace(b"preferWindowsFramework:o=!1", b"preferWindowsFramework:o=0", 1)
    )
    if len(renamed_status) != len(status_match.group()):
        sys.exit("renamed primary-runtime status function changed byte length")
    data = replace_regex(
        data,
        PRIMARY_RUNTIME_STATUS,
        renamed_status,
        "primary-runtime status",
    )
    data = replace_regex(
        data,
        PRIMARY_RUNTIME_INSTALL,
        PRIMARY_RUNTIME_STATUS_WRAPPER + PRIMARY_RUNTIME_INSTALL_WRAPPER,
        "primary-runtime installer",
    )
    asar.write_bytes(data)


if __name__ == "__main__":
    main()
