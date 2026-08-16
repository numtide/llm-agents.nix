# pnpm-bin: the pnpm npm package (self-contained JS bundle) run on the node
# toolchain - no separate binary to patchelf. version + hash (arch-independent)
# from ./hashes.json. `pnpm` execs `node dist/pnpm.cjs`, inheriting node's
# pinned-glibc runtime.
scope:
let
  inherit (scope) fetchurl mkDrvSh;
  node = scope.nodeBin;
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (data) version;
  tgz = fetchurl {
    url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
    inherit (data) hash;
    name = "pnpm-${version}.tgz";
  };
in
mkDrvSh {
  name = "pnpm-${version}";
  env = { inherit tgz node; };
  script = ''
    mkdir -p "$out/libexec/pnpm" "$out/bin"
    tar -xzf "$tgz" -C "$out/libexec/pnpm" --strip-components=1
    {
      echo "#!/bin/sh"
      echo "exec \"$node/bin/node\" \"$out/libexec/pnpm/dist/pnpm.cjs\" \"\$@\""
    } > "$out/bin/pnpm"
    chmod +x "$out/bin/pnpm"
    "$out/bin/pnpm" --version > "$out/version.txt"
  '';
}
