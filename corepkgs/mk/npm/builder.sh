#!/bin/sh
# mkNpm builder. mkDrvSh puts busybox on PATH and runs us under `set -eu`.
# Env: see mk/npm/default.nix. $customWrapperScript is caller-supplied bin
# wrappers (shell), eval'd at the end.
# shellcheck disable=SC2154,SC2164 # env vars; set -eu aborts on cd failure
export HOME="$NIX_BUILD_TOP"
export npm_config_cache="$NIX_BUILD_TOP/.npm"
export npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
export PATH="$node/bin:$PATH"

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

# drop in the vendored node_modules (the FOD is read-only)
cp -r "$vendor" node_modules
chmod -R u+w node_modules

# patchShebangs: the sandbox has no /usr/bin/env, so rewrite every
# `#!/usr/bin/env node` in node_modules/.bin targets to our node. Else
# `npm run build` -> tsc/esbuild fail with "not found".
npm_cli="$node/lib/node_modules/npm/bin/npm-cli.js"
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

# build (tsc/esbuild/... via the package's own script). Invoke npm through
# node (the `npm` bin symlink has the same /usr/bin/env shebang problem).
[ -n "$buildScript" ] && "$node/bin/node" "$npm_cli" run "$buildScript"

# install the whole package under $out/lib/node_modules/<pname>
dest="$out/lib/node_modules/$pname"
mkdir -p "$dest" "$out/bin"
cp -r . "$dest/"

# patchelf bundled prebuilt native addons (*.node / *.bare) to the pinned
# glibc, so they resolve inside the store instead of the host FHS.
if [ -n "$nativeAddons" ]; then
  find "$dest" \( -name '*.node' -o -name '*.bare' \) -type f | while read -r so; do
    [ "$(head -c4 "$so" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
    "$formatelf/bin/formatelf" --force-rpath --set-rpath "$addonRpath" "$so" 2>/dev/null || true
  done
fi

if [ -z "$customBins" ]; then
  # wrap each package.json "bin" as a node launcher on $out/bin
  node -e '
    const p = require("./package.json");
    let bin = p.bin || {};
    if (typeof bin === "string") bin = { [p.name.replace(/^@[^/]+\//,"")]: bin };
    for (const [k, v] of Object.entries(bin)) console.log(k + " " + String(v).replace(/^\.\//, ""));
  ' | while read -r name entry; do
    [ -n "$name" ] || continue
    {
      echo "#!/bin/sh"
      echo "exec \"$node/bin/node\" \"$dest/$entry\" \"\$@\""
    } >"$out/bin/$name"
    chmod +x "$out/bin/$name"
  done
fi

# caller-supplied wrappers (extra node flags / env / PATH / corrected entry)
eval "$customWrapperScript"
