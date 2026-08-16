# showboat - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
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
  pname = "showboat";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/simonw/showboat/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  binaries = [ "showboat" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${data.version}"
  ];

  category = "Utilities";
  meta = {
    description = "Create executable demo documents showing and proving an agent's work";
    homepage = "https://github.com/simonw/showboat";
    changelog = "https://github.com/simonw/showboat/releases/tag/v${data.version}";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.jfroche ];
  };
}
