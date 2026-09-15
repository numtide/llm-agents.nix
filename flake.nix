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
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs."nixpkgs".follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs."nixpkgs-lib".follows = "nixpkgs";
    };
    bun2nix = {
      # https://github.com/nix-community/bun2nix/pull/106
      url = "github:Mic92/bun2nix/fix-structured-attrs-hook";
      inputs."nixpkgs".follows = "nixpkgs";
      inputs."systems".follows = "systems";
      inputs."treefmt-nix".follows = "treefmt-nix";
      inputs."flake-parts".follows = "flake-parts";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      eachSystem = lib.genAttrs systems;

      # The flake itself, as passed to packages/checks (`flake.lib`,
      # `flake.inputs`, source path via string interpolation).
      flake = self // {
        inherit inputs;
      };

      # Call a function with only the arguments it declares.
      callWith = args: fn: fn (builtins.intersectAttrs (builtins.functionArgs fn) args);

      packageNames = builtins.attrNames (
        lib.filterAttrs (_name: type: type == "directory") (builtins.readDir ./packages)
      );

      checkNames = lib.mapAttrsToList (name: _type: lib.removeSuffix ".nix" name) (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
          builtins.readDir ./checks
        )
      );

      pkgsFor = eachSystem (system: import nixpkgs { inherit system; });

      # Every package under packages/, built against the given package set.
      #
      # Each package.nix is called from a scope containing all in-repo
      # packages plus shared helpers, so dependencies like `wrapBuddy` or
      # `platformSource` resolve by argument name.
      mkPackagesFor =
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;

          # Generic {name}-template interpolation (Nix mirror of str.format) and
          # a templated fetchurl built on it — the single templated-URL primitive
          # shared between a package's build and its declarative updater.
          interpolate = import ./lib/interpolate.nix;
          fetchurlTemplate = import ./lib/fetchurl-template.nix {
            inherit (pkgs) fetchurl;
            inherit interpolate;
          };

          # Route bun2nix's per-dep fetches through naked-fetchurl: ~3.4s (~15%)
          # off eval, all in the bun packages. Output paths unchanged (FODs),
          # only bun-cache .drv inputs differ, so it is a one-time cache rebuild.
          pkgsBun = pkgs // {
            fetchurl = import ./lib/naked-fetchurl.nix;
          };

          scope = lib.makeScope pkgs.newScope (
            self:
            {
              inherit
                flake
                inputs
                system
                interpolate
                fetchurlTemplate
                ;
              platformSource = import ./lib/platform-source.nix {
                inherit (pkgs) lib stdenv;
                inherit fetchurlTemplate;
              };
              # Validate a declarative passthru.updater config (see
              # scripts/updater/run.py); packages opt out of update.py with it.
              mkUpdater = import ./lib/mk-updater.nix { inherit (pkgs) lib; };
              # `bun build --compile` copies the running bun binary into the
              # executable it produces, so bun ends up inside our outputs
              # rather than being a build tool we can leave to the consumer.
              # bun 1.3.14 miscomputes where its own runtime image ends once
              # patchelf has rewritten the ELF, and emits a standalone binary
              # that embeds the runtime twice and segfaults on startup. Via
              # overlays.shared-nixpkgs we get whatever bun the consumer's
              # overlays provide, so take bun from our own nixpkgs instead.
              # Pinning it also keeps the bun packages substitutable for
              # shared-nixpkgs consumers, whose bun would otherwise change
              # every store path in the set.
              bun = pkgsFor.${system}.bun or pkgs.bun;
              # bun2nix builder set (hook, fetchBunDeps, ...); the `bun2nix`
              # scope attribute is the CLI package. Apply the overlay directly
              # (final=prev=pkgs) instead of pkgs.extend, which would re-run the
              # whole nixpkgs fixpoint just to add this one leaf (~5s of eval).
              bun2nixLib = (inputs."bun2nix".overlays.default pkgsBun pkgsBun).bun2nix;
              # makeScope reserves `packages`, so expose the package set as allPackages.
              allPackages = packages;
            }
            // lib.genAttrs packageNames (name: self.callPackage (./packages + "/${name}/package.nix") { })
          );

          # Generate a standard passthru.updateScript from a package's
          # declarative passthru.updater config (see lib/mk-update-script.nix).
          mkUpdateScript = import ./lib/mk-update-script.nix {
            inherit (pkgs)
              lib
              writeShellApplication
              nix
              git
              cacert
              bun
              nodejs
              ;
            python3 = pkgs.python3;
          };

          # Attach passthru.updateScript to any package carrying passthru.updater,
          # so one `nix run .#<pkg>.updateScript` drives every declarative updater.
          withUpdateScript =
            name: pkg:
            if pkg ? updater then
              pkg.overrideAttrs (old: {
                passthru = (old.passthru or { }) // {
                  updateScript = mkUpdateScript {
                    inherit name;
                    config = pkg.updater;
                  };
                };
              })
            else
              pkg;

          # Only the packages, without the scope plumbing and helpers.
          packages = lib.mapAttrs withUpdateScript (lib.genAttrs packageNames (name: scope.${name}));
        in
        packages;

      # Every package under packages/, independent of the current platform.
      allPackages = eachSystem (system: mkPackagesFor pkgsFor.${system});

      # Only expose packages that build on the given platform.
      available =
        system: pkg:
        lib.meta.availableOn pkgsFor.${system}.stdenv.hostPlatform pkg && !(pkg.meta.broken or false);

      packages = eachSystem (system: lib.filterAttrs (_name: available system) allPackages.${system});

      devShells = eachSystem (system: {
        default = callWith {
          pkgs = pkgsFor.${system};
          perSystem = {
            self = allPackages.${system};
          };
          inherit flake inputs system;
        } (import ./devshell.nix);
      });
    in
    {
      lib = import ./lib { inherit inputs; };

      inherit packages devShells;

      overlays.shared-nixpkgs = import ./overlays/shared-nixpkgs.nix {
        inherit mkPackagesFor;
      };

      formatter = eachSystem (system: allPackages.${system}.formatter);

      # Publishes the package search site to gh-pages via nixbot effects.
      herculesCI = import ./lib/hercules-ci.nix {
        pkgs = pkgsFor.x86_64-linux;
        site = packages.x86_64-linux.site;
      };

      checks = eachSystem (
        system:
        lib.mapAttrs' (name: pkg: lib.nameValuePair "pkgs-${name}" pkg) packages.${system}
        // lib.genAttrs checkNames (
          name:
          callWith {
            pkgs = pkgsFor.${system};
            inherit flake inputs system;
          } (import (./checks + "/${name}.nix"))
        )
        // {
          devshell-default = devShells.${system}.default;
        }
      );
    };
}
