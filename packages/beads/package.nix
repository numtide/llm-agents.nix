# beads - built from source on corepkgs (nixpkgs-free) via mkGo with cgo. It
# links ICU via go-icu-regex's cgo. zig cc compiles the cgo C; the dynamic
# output is patchelf'd to the pinned glibc + icu. buildInputs pass icu (lib for
# rpath) + icuDev (pkgconfig/headers). Note: upstream wraps bd with dolt on
# PATH; mkGo does not wrap, so dolt must be provided at runtime separately.
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
  pname = "beads";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/gastownhall/beads/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  cgo = true;
  buildInputs = [
    corePins.icu
    corePins.icuDev
  ];
  subPackages = [ "cmd/bd" ];
  binaries = [ "bd" ];
  category = "Workflow & Project Management";
  meta = {
    description = "A distributed issue tracker designed for AI-supervised coding workflows";
    homepage = "https://github.com/gastownhall/beads";
    changelog = "https://github.com/gastownhall/beads/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.zimbatm ];
  };
}
