# entire - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
# so the output is a fully static binary (no glibc, no patchelf). Modules are
# vendored by a single vendorHash FOD. Requires a go >= 1.26.4 toolchain (mkGo
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
  pname = "entire";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/entireio/cli/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/entire" ];
  binaries = [ "entire" ];
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/entireio/cli/cmd/entire/cli/versioninfo.Version=${data.version}"
  ];

  category = "Usage Analytics";
  meta = {
    description = "CLI tool that captures AI agent sessions and links them to code changes";
    homepage = "https://github.com/entireio/cli";
    changelog = "https://github.com/entireio/cli/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.yutakobayashidev ];
  };
}
