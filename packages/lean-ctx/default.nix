{
  pkgs,
  perSystem,
  flake,
  ...
}:
pkgs.callPackage ./package.nix {
  inherit (perSystem.self) versionCheckHomeHook;
  inherit flake;
}
