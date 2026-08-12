{
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  bun2nix = (pkgs.extend flake.inputs."bun2nix".overlays.default).bun2nix;
in
pkgs.callPackage ./package.nix {
  inherit flake bun2nix;
  inherit (perSystem.self) versionCheckHomeHook;
}
