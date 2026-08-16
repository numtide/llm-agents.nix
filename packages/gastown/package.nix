# gastown - built from source on corepkgs (nixpkgs-free) via mkGo with cgo (it
# links ICU via cgo). zig cc compiles the cgo C; the dynamic output is patchelf'd
# to the pinned glibc + icu. buildInputs pass icu (lib for rpath) + icuDev
# (pkgconfig/headers for the #cgo pkg-config).
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
  pname = "gastown";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/gastownhall/gastown/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  cgo = true;
  buildInputs = [
    corePins.icu
    corePins.icuDev
  ];
  subPackages = [ "cmd/gt" ];
  binaries = [ "gt" ];
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/steveyegge/gastown/internal/cmd.Version=${data.version}"
    "-X=github.com/steveyegge/gastown/internal/cmd.Build=release"
    "-X=github.com/steveyegge/gastown/internal/cmd.BuiltProperly=1"
  ];
  category = "Workflow & Project Management";
  meta = {
    description = "Gas Town - multi-agent workspace manager";
    homepage = "https://github.com/gastownhall/gastown";
    changelog = "https://github.com/gastownhall/gastown/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.zaninime ];
  };
}
