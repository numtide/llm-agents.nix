# gascity - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
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
  pname = "gascity";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/gastownhall/gascity/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/gc" ];
  binaries = [ "gc" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${data.version}"
    "-X=main.commit=nixpkgs"
    "-X=main.date=1970-01-01T00:00:00Z"
  ];

  category = "Workflow & Project Management";
  meta = {
    description = "Orchestration-builder SDK for multi-agent coding workflows";
    homepage = "https://github.com/gastownhall/gascity";
    changelog = "https://github.com/gastownhall/gascity/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.zaninime ];
    mainProgram = "gc";
  };
}
