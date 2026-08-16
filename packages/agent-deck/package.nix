# agent-deck - built from source on corepkgs (nixpkgs-free) via mkGo.
# CGO_ENABLED=0, so the output is a fully static binary (no glibc, no patchelf).
# Modules are vendored by a single vendorHash FOD.
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "agent-deck";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/asheshgoplani/agent-deck/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/agent-deck" ];
  binaries = [ "agent-deck" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.Version=${data.version}"
  ];

  category = "Workflow & Project Management";
  meta = {
    description = "Your AI agent command center";
    homepage = "https://github.com/asheshgoplani/agent-deck";
    changelog = "https://github.com/asheshgoplani/agent-deck/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.garbas ];
  };
}
