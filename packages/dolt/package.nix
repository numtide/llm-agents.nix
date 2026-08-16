# dolt - built from source on corepkgs (nixpkgs-free) via mkGo with cgo (it
# links ICU via cgo). zig cc compiles the cgo C; the dynamic output is patchelf'd
# to the pinned glibc + icu. buildInputs pass icu (lib for rpath) + icuDev
# (pkgconfig/headers for the #cgo pkg-config). go.mod lives in ./go.
{
  mkGo,
  coreFetchurl,
  corePins,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "dolt";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/dolthub/dolt/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  cgo = true;
  buildInputs = [
    corePins.icu
    corePins.icuDev
  ];
  sourceRoot = "go";
  subPackages = [ "cmd/dolt" ];
  binaries = [ "dolt" ];
  ldflags = [ "-buildid=" ];
  category = "Utilities";
  meta = {
    description = "Relational database with version control and CLI a-la Git";
    homepage = "https://github.com/dolthub/dolt";
    changelog = "https://github.com/dolthub/dolt/releases/tag/v${data.version}";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
  };
}
