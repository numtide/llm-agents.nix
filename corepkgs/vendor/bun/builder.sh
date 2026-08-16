#!/bin/sh
# bun-vendor FOD. Env: $src, $sourceRoot, $bun. mkDrvSh puts busybox on PATH and
# runs us under `set -eu`. Output at $out.
# shellcheck disable=SC2154,SC2164 # src/sourceRoot/bun/out are build-env vars; set -eu (prelude) aborts on cd failure
export PATH="$bun/bin:$PATH"

export HOME="$NIX_BUILD_TOP"
export BUN_INSTALL="$NIX_BUILD_TOP/.bun"

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

bun install --frozen-lockfile --ignore-scripts --no-progress
cp -r node_modules "$out"
