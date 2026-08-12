{
  pkgs,
  flake,
  perSystem,
  cudaSupport ? pkgs.config.cudaSupport or false,
  ...
}:
let
  bun2nix = (pkgs.extend flake.inputs."bun2nix".overlays.default).bun2nix;
in
pkgs.callPackage ./package.nix {
  inherit flake cudaSupport bun2nix;
  inherit (pkgs) vulkan-loader autoAddDriverRunpath cudaPackages;
  autoPatchelfHook = perSystem.self.formatelf;
}
