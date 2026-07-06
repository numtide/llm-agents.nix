{
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  bun2nix = (pkgs.extend flake.inputs.bun2nix.overlays.default).bun2nix;
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  semVersionData = {
    version = versionData.semVersion;
    hash = versionData.semHash;
    cargoHash = versionData.semCargoHash;
  };
  plannotatorSem = pkgs.callPackage ../sem/package.nix { versionData = semVersionData; };
in
pkgs.callPackage ./package.nix {
  inherit bun2nix plannotatorSem;
  inherit (perSystem.self) versionCheckHomeHook;
}
