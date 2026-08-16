# td - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
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
  pname = "td";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/marcus/td/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  binaries = [ "td" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.Version=${data.version}"
  ];

  category = "Workflow & Project Management";
  meta = {
    description = "A minimalist CLI for tracking tasks across AI coding sessions.";
    homepage = "https://github.com/marcus/td";
    changelog = "https://github.com/marcus/td/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.afterthought ];
  };
}
