{
  pkgs,
  flake,
  ...
}:
pkgs.callPackage ./package.nix { inherit flake; }
