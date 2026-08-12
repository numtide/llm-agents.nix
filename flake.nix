{
  description = "Exploring integration between Nix and AI coding agents";
  nixConfig = {
    allow-import-from-derivation = false;
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    blueprint = {
      url = "github:numtide/blueprint";
      inputs."nixpkgs".follows = "nixpkgs";
      inputs."systems".follows = "systems";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs."nixpkgs".follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs."nixpkgs-lib".follows = "nixpkgs";
    };
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs."nixpkgs".follows = "nixpkgs";
      inputs."systems".follows = "systems";
      inputs."treefmt-nix".follows = "treefmt-nix";
      inputs."flake-parts".follows = "flake-parts";
    };
  };

  outputs =
    inputs:
    let
      blueprintOutputs = inputs."blueprint" {
        inherit inputs;
        nixpkgs.config.allowUnfree = true;
      };

    in
    blueprintOutputs
    // {
      overlays = {
        default = import ./overlays {
          inherit (blueprintOutputs) packages;
        };
        shared-nixpkgs = import ./overlays/shared-nixpkgs.nix {
          inherit (blueprintOutputs) mkPackagesFor;
        };
      };
    };
}
