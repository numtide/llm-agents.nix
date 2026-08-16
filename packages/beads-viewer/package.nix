# beads-viewer - built from source on corepkgs (nixpkgs-free) via mkGo, static
# (CGO_ENABLED=0). No external deps (stdlib only), so no vendorHash.
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "beads-viewer";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/Dicklesworthstone/beads_viewer/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  subPackages = [ "cmd/bv" ];
  binaries = [ "bv" ];
  ldflags = [
    "-s"
    "-w"
    "-X github.com/Dicklesworthstone/beads_viewer/pkg/version.version=v${data.version}"
  ];
  category = "Workflow & Project Management";
  meta = {
    description = "Graph-aware TUI for the Beads issue tracker";
    homepage = "https://github.com/Dicklesworthstone/beads_viewer";
    changelog = "https://github.com/Dicklesworthstone/beads_viewer/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.afterthought ];
  };
}
