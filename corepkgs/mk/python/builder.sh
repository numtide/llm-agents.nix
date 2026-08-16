#!/bin/sh
# mkPython builder. mkDrvSh puts busybox on PATH and runs us under `set -eu`.
# Env: $vendor (site tree FOD), $python, $out, $wrapperScript (per-entrypoint
# launchers, eval'd).
# shellcheck disable=SC2154 # vendor/python/out/wrapperScript are build-env vars
mkdir -p "$out/bin" "$out/lib"
# the vendored site tree (app + deps) becomes $out/lib/pysite
cp -r "$vendor" "$out/lib/pysite"
chmod -R u+w "$out/lib/pysite"
eval "$wrapperScript"
