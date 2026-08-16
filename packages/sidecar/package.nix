# sidecar - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
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
  pname = "sidecar";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/marcus/sidecar/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/sidecar" ];
  binaries = [ "sidecar" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.Version=${data.version}"
  ];

  category = "Workflow & Project Management";
  meta = {
    description = "Terminal-based development companion for AI coding agents";
    homepage = "https://github.com/marcus/sidecar";
    changelog = "https://github.com/marcus/sidecar/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.afterthought ];
  };
}
