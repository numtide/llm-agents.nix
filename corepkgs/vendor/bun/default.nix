# Vendor a bun project's deps as ONE fixed-output derivation: `bun install
# --frozen-lockfile` from bun.lock produces node_modules, which we output. bun's
# integrity hashes aren't a single fetchurl input, so it's one committed-hash
# FOD. --ignore-scripts keeps it deterministic + compiler-free (native deps ship
# prebuilt binaries bun fetches without a build step).
scope:
{
  src,
  bunDepsHash,
  sourceRoot ? null,
  bun, # the bun toolchain, threaded from the constructor scope
}:
let
  inherit (scope) mkDrvSh;
in
mkDrvSh {
  name = "bun-vendor";
  outputHash = bunDepsHash;
  env = {
    inherit src;
    sourceRoot = if sourceRoot == null then "" else sourceRoot;
    bun = "${bun}";
  };
  script = ./builder.sh;
}
