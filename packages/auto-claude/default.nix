{
  pkgs,
  flake,
  ...
}:
let
  npmPackumentSupport = pkgs.callPackage ../../lib/fetch-npm-deps.nix { };
in
pkgs.callPackage ./package.nix {
  inherit flake;
  inherit (npmPackumentSupport) fetchNpmDepsWithPackuments npmConfigHook;
}
