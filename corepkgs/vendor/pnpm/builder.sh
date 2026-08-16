#!/bin/sh
# pnpm-vendor FOD. Env: $src, $sourceRoot, $postPatch, $pnpm, $node. mkDrvSh puts
# busybox on PATH and runs us under `set -eu`. Output at $out.
# shellcheck disable=SC2154,SC2164 # src/sourceRoot/postPatch/pnpm/node/out are build-env vars; set -eu (prelude) aborts on cd failure
export PATH="$pnpm/bin:$node/bin:$PATH"

export HOME="$NIX_BUILD_TOP"

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"
eval "$postPatch"

pnpm install --frozen-lockfile --ignore-scripts \
  --config.node-linker=hoisted \
  --config.store-dir="$NIX_BUILD_TOP/.pnpm-store" \
  --config.confirmModulesPurge=false

# cp -r (NOT -L): pnpm hardlinks store files into node_modules (cp copies
# them as real files -> self-contained), but .bin entries are RELATIVE
# symlinks that must stay symlinks; dereferencing relocates a bin's relative
# requires and breaks it (e.g. .bin/tsc's `import "../lib/tsc.js"`).
cp -r node_modules "$out"
