# fence - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
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
  pname = "fence";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/fencesandbox/fence/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/fence" ];
  binaries = [ "fence" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${data.version}"
    "-X=main.buildTime=1970-01-01T00:00:00Z"
    "-X=main.gitCommit=v${data.version}"
  ];

  category = "Sandboxing & Isolation";
  meta = {
    description = "Lightweight, container-free sandbox for running commands with network and filesystem restrictions";
    homepage = "https://fencesandbox.com/";
    changelog = "https://github.com/fencesandbox/fence/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.uesyn ];
    mainProgram = "fence";
  };
}
