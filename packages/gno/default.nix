{
  pkgs,
  flake,
  cudaSupport ? pkgs.config.cudaSupport or false,
  ...
}:
let
  npmPackumentSupport = pkgs.callPackage ../../lib/fetch-npm-deps.nix { };
in
pkgs.callPackage ./package.nix {
  inherit flake cudaSupport;
  inherit (npmPackumentSupport) fetchNpmDepsWithPackuments npmConfigHook;
  inherit (pkgs) vulkan-loader autoAddDriverRunpath;
  inherit (pkgs) cudaPackages;
}
