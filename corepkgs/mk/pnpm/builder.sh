#!/bin/sh
# mkPnpm builder. mkDrvSh puts busybox on PATH and runs us under `set -eu`.
# Env: see mk/pnpm/default.nix. $postPatch is caller shell run before the build.
# shellcheck disable=SC2154,SC2164 # env vars; set -eu aborts on cd failure
export HOME="$NIX_BUILD_TOP"
export PATH="$pnpm/bin:$node/bin:$PATH"
# native build tools (esbuild/... via .node) need libstdc++ at build time
export LD_LIBRARY_PATH="$libpath"

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"
eval "$postPatch"

# drop in the vendored node_modules (the FOD is read-only)
cp -r "$vendor" node_modules
chmod -R u+w node_modules

# patchShebangs: the sandbox has no /usr/bin/env, so rewrite the
# `#!/usr/bin/env node` in node_modules/.bin targets to our node.
for l in node_modules/.bin/*; do
  [ -e "$l" ] || continue
  t=$(readlink -f "$l" 2>/dev/null) || continue
  [ -f "$t" ] || continue
  case "$(head -1 "$t" 2>/dev/null)" in
  "#!/usr/bin/env node"* | "#! /usr/bin/env node"* | "#!/usr/bin/node"*)
    sed -i "1s|.*|#!$node/bin/node|" "$t"
    ;;
  esac
done

# build (tsc/vite/... via the package's own script). Set via .npmrc, not env
# (nested `pnpm --filter` runs drop env): offline + disable package-manager
# self-management (pnpm 10 else fetches the "packageManager" pnpm, fails offline).
printf 'offline=true\nmanage-package-manager-versions=false\n' >>.npmrc
[ -n "$buildScript" ] && pnpm run "$buildScript"

# install dist + node_modules + package.json under $out/lib/<pname>
dest="$out/lib/$pname"
mkdir -p "$dest" "$out/bin"
cp -r . "$dest/"

# patchelf bundled prebuilt native addons (*.node) to the pinned glibc.
find "$dest" -name '*.node' -type f | while read -r so; do
  [ "$(head -c4 "$so" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
  "$formatelf/bin/formatelf" --force-rpath --set-rpath "$libpath" "$so" 2>/dev/null || true
done

# wrapper: run the built entry on the pinned node toolchain
{
  echo "#!/bin/sh"
  echo "exec \"$node/bin/node\" \"$dest/$entry\" \"\$@\""
} >"$out/bin/$mainProgram"
chmod +x "$out/bin/$mainProgram"
