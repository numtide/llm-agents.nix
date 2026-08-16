#!/bin/sh
# npm-vendor FOD. Env: $src, $sourceRoot, $packageLock, $omitFlag, $node.
# mkDrvSh puts busybox on PATH and runs us under `set -eu`. Output at $out.
# shellcheck disable=SC2154,SC2164 # all-caps/env names are build-env vars; set -eu (prelude) aborts on cd failure
export PATH="$node/bin:$PATH"

export HOME="$NIX_BUILD_TOP"
export npm_config_cache="$NIX_BUILD_TOP/.npm"
export npm_config_update_notifier=false
export npm_config_fund=false
export npm_config_audit=false

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

[ -n "$packageLock" ] && cp "$packageLock" package-lock.json
# shellcheck disable=SC2086 # $omitFlag is intentionally split (flag or nothing)
npm ci --ignore-scripts --no-audit --no-fund $omitFlag
cp -r node_modules "$out"
