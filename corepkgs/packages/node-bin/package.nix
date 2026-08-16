# node-bin: upstream prebuilt nodejs tarball. version + per-system hash from
# ./hashes.json, platform token from systems.nix.
# node is a plain dynamic executable (no appended payload), so patchelf is safe:
# set the pinned glibc interpreter + rpath.
scope:
let
  inherit (scope)
    fetchurl
    mkDrvSh
    systems
    system
    pins
    ;
  sys = systems.${system};
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  inherit (data) version;
  plat = sys.node.platform;
  dir = "node-v${version}-${plat}";
  tarball = fetchurl {
    url = "https://nodejs.org/dist/v${version}/${dir}.tar.gz";
    hash = data.hashes.${system};
  };
in
mkDrvSh {
  name = "nodejs-${version}";
  env = {
    inherit tarball;
    glibc = pins.glibc;
    formatelf = pins.formatelf;
    gccLib = pins.gccLib;
  };
  script = ''
    tar -xzf "$tarball"
    cp -r "${dir}" "$out"
    chmod -R u+w "$out"

    "$formatelf/bin/formatelf" \
      --set-interpreter "$glibc/lib/${sys.loader}" \
      --set-rpath "$glibc/lib:$gccLib/lib" \
      "$out/bin/node"

    "$out/bin/node" --version > "$out/node-version.txt"
  '';
}
