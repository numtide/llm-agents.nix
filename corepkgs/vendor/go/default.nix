# Vendor a go module's deps as ONE fixed-output derivation: `go mod vendor` runs
# with network, caller commits the hash. go.sum records h1: tree hashes, not
# fetchurl-compatible, so unlike cargo we can't do per-dep FODs. Deterministic
# given go.sum.
scope:
{
  src,
  vendorHash,
  sourceRoot ? null,
  go, # the go toolchain, threaded from the constructor scope
}:
let
  inherit (scope) mkDrvSh;
in
mkDrvSh {
  name = "go-vendor";
  outputHash = vendorHash;
  env = {
    inherit src;
    sourceRoot = if sourceRoot == null then "" else sourceRoot;
    go = "${go}";
  };
  script = ./builder.sh;
}
