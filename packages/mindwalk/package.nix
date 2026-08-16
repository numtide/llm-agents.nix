# mindwalk - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
# so the output is a fully static binary (no glibc, no patchelf). Modules are
# vendored by a single vendorHash FOD (go.sum hashes are not fetchurl-compatible).
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "mindwalk";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/cosmtrek/mindwalk/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/mindwalk" ];
  binaries = [ "mindwalk" ];
  ldflags = [
    "-s"
    "-w"
  ];

  category = "Usage Analytics";
  meta = {
    description = "Visualization tool that replays coding-agent sessions on a 3D map of your codebase";
    homepage = "https://github.com/cosmtrek/mindwalk";
    changelog = "https://github.com/cosmtrek/mindwalk/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.zimbatm ];
  };
}
