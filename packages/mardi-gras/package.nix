# mardi-gras - built from source on corepkgs (nixpkgs-free) via mkGo.
# CGO_ENABLED=0, so the output is a fully static binary (no glibc, no patchelf).
# Modules are vendored by a single vendorHash FOD (go.sum hashes are not
# fetchurl-compatible).
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "mardi-gras";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/quietpublish/mardi-gras/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/mg" ];
  binaries = [ "mg" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${data.version}"
  ];

  category = "Workflow & Project Management";
  meta = {
    description = "Terminal UI for Beads issue tracking with a parade-inspired workflow view";
    homepage = "https://github.com/quietpublish/mardi-gras";
    changelog = "https://github.com/quietpublish/mardi-gras/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.smdex ];
    mainProgram = "mg";
  };
}
