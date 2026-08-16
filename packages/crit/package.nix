# crit - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
# so the output is a fully static binary (no glibc, no patchelf). Modules are
# vendored by a single vendorHash FOD. Requires a go >= 1.26 toolchain (mkGo
# ships 1.26.x).
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "crit";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/tomasz-tomczyk/crit/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/crit" ];
  binaries = [ "crit" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${data.version}"
  ];

  category = "Code Review";
  meta = {
    description = "Local-first review tool for coding-agent plans, diffs, and web pages";
    homepage = "https://github.com/tomasz-tomczyk/crit";
    changelog = "https://github.com/tomasz-tomczyk/crit/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.ahacop ];
  };
}
