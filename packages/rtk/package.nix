# rtk - built from source on corepkgs (nixpkgs-free) via mkCargo. rusqlite's
# bundled sqlite C compiles via zig cc. (Upstream wraps shell hooks with jq in a
# postInstall; that is dropped here - cosmetic, not a build concern.)
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "rtk";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/rtk-ai/rtk/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "rtk" ];

  category = "Utilities";
  meta = {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    changelog = "https://github.com/rtk-ai/rtk/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.vizid ];
  };
}
