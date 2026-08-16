#!/bin/sh
# mkBun builder. mkDrvSh puts busybox on PATH and runs us under `set -eu`.
# Env: see mk/bun/default.nix.
# shellcheck disable=SC2154,SC2164,SC2086 # env vars; set -eu aborts on cd; $buildScript split on purpose
export HOME="$NIX_BUILD_TOP"
export PATH="$bun/bin:$PATH"
export LD_LIBRARY_PATH="$libpath"
export BUN_INSTALL="$NIX_BUILD_TOP/.bun"
export BUN_TMPDIR="$NIX_BUILD_TOP/.bun-tmp"
mkdir -p "$BUN_TMPDIR"

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

# drop in the vendored node_modules (the FOD is read-only)
cp -r "$vendor" node_modules
chmod -R u+w node_modules

# bun's offline resolver refuses semver ranges (^/~) when only the pinned
# version is present; collapse them to exact pins so bun skips the blocked
# registry lookup.
for f in package.json packages/*/package.json bun.lock; do
  [ -f "$f" ] && sed -i 's/: "\^/: "/g; s/: "~/: "/g' "$f"
done

# optional pre-run build (assets/tailwind/...) in place
[ -n "$buildScript" ] && bun $buildScript

# install the whole app (source + node_modules) under $out/lib/<pname>
dest="$out/lib/$pname"
mkdir -p "$dest" "$out/bin"
cp -r . "$dest/"

# bun vendors its own platform binaries (@oven/bun-<platform>) as optional deps.
# We run on the toolchain bun, so these are never invoked - and they are FHS-
# linked musl/glibc ELFs that fail the store-only check. Drop them.
for d in "$dest"/node_modules/.bun/@oven+bun-* "$dest"/node_modules/@oven/bun-*; do
  [ -e "$d" ] && rm -rf "$d"
done

# patchelf bundled prebuilt native addons (*.node) to the pinned glibc so
# they resolve inside the store instead of the host FHS.
find "$dest" -name '*.node' -type f | while read -r so; do
  [ "$(head -c4 "$so" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
  "$formatelf/bin/formatelf" --force-rpath --set-rpath "$libpath" "$so" 2>/dev/null || true
done

# wrapper: run the entry on the pinned bun toolchain
{
  echo "#!/bin/sh"
  echo "exec \"$bun/bin/bun\" run \"$dest/$entry\" \"\$@\""
} >"$out/bin/$mainProgram"
chmod +x "$out/bin/$mainProgram"
