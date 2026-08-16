#!/bin/sh
# python-vendor FOD. Env: $src, $sourceRoot, $postPatch, $python. mkDrvSh puts
# busybox on PATH and runs us under `set -eu`. Output at $out.
# shellcheck disable=SC2154,SC2164 # src/sourceRoot/postPatch/python/out are build-env vars; set -eu (prelude) aborts on cd failure
export PATH="$python/bin:$PATH"

export HOME="$NIX_BUILD_TOP"
export PIP_DISABLE_PIP_VERSION_CHECK=1

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"
eval "$postPatch"

# build the app + resolve the whole runtime closure into a flat site tree
python3 -m pip install --target "$out" --no-compile --no-warn-script-location .

# strip nondeterministic install bookkeeping so the FOD hash is stable
find "$out" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$out" \( -name 'RECORD' -o -name 'direct_url.json' \) -delete 2>/dev/null || true

# pip's console scripts carry a `#!<toolchain python>` shebang -> the tree
# references a store path, forbidden in a FOD (its hash can't capture refs).
# mkPython regenerates launchers from `entrypoints`, so drop pip's bin/.
rm -rf "${out:?}/bin"
