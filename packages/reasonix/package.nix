# reasonix - built from source on corepkgs (nixpkgs-free) via mkGo. CGO_ENABLED=0,
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
  pname = "reasonix";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/esengine/DeepSeek-Reasonix/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/reasonix" ];
  binaries = [ "reasonix" ];
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=v${data.version}"
  ];

  category = "AI Coding Agents";
  meta = {
    description = "DeepSeek-native AI coding agent for your terminal";
    homepage = "https://github.com/esengine/DeepSeek-Reasonix";
    changelog = "https://github.com/esengine/DeepSeek-Reasonix/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.arch-fan ];
  };
}
