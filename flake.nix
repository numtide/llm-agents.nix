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
      url = "github:nix-community/bun2nix";
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

      # corepkgs' system-independent API, for the meta helpers (flakeLib, ...).
      # The system arg is a formality these functions never force; the
      # per-system builder API is bound as `core` inside each system below.
      coreApi = (import ./corepkgs { system = builtins.head systems; }).lib;

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

      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          inherit system;
          # keep GHC out of eval: writeShellApplication's build-time shellcheck
          # lint drags in the whole Haskell closure; we lint shell with shuck.
          # no-ghc.nix is the tripwire that forbids Haskell from creeping back.
          overlays = [
            (import ./overlays/no-shellcheck-wrappers.nix)
            (import ./overlays/no-pandoc.nix)
            (import ./overlays/no-ghc.nix)
          ];
        }
      );

      # Every package under packages/, built against the given package set.
      #
      # Each package.nix is called from a scope containing all in-repo
      # packages plus shared helpers, so dependencies like `wrapBuddy` or
      # `platformSource` resolve by argument name.
      mkPackagesFor =
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;

          # corepkgs, the nixpkgs-free packaging system, as an importable API
          # (corepkgs/default.nix). `core.lib` is the builder API + owned
          # primitives (system/pins pre-bound); `core.pins` the pkgs-sourced pins.
          core = import ./corepkgs { inherit system pkgs; };

          # All fetcher machinery (interpolate, fetchurl-template, platform-source)
          # lives in corepkgs/fetch and is exposed via core.lib.
          interpolate = core.lib.interpolate;
          fetchurlTemplate = core.lib.fetchurlTemplate;

          # Route bun2nix's per-dep fetches through core-fetchurl: ~3.4s (~15%)
          # off eval, all in the bun packages. Output paths unchanged (FODs),
          # only bun-cache .drv inputs differ, so it is a one-time cache rebuild.
          pkgsBun = pkgs // {
            fetchurl = core.lib.coreFetchurl;
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
              platformSource = core.lib.platformSource;
              # corepkgs: the nixpkgs-free packaging system (corepkgs/). A
              # package.nix that declares `mkPackage` is a corepkgs build —
              # callPackage resolves it from the scope, so no routing is needed.
              # The builders come from core.lib (system/pins pre-bound), so
              # package.nix stays terse; `coreFetchurl` is corepkgs' builtin
              # fetchurl under a non-clashing name (inline side-downloads without
              # shadowing pkgs.fetchurl for the nixpkgs packages).
              corePins = core.pins;
              inherit (core.lib)
                mkPackage
                mkCargo
                mkGo
                mkNpm
                mkBun
                mkPnpm
                mkPython
                mkDrv
                checkFhs
                coreFetchurl
                ;
              # Validate a declarative passthru.updater config (see
              # scripts/updater/run.py); packages opt out of update.py with it.
              mkUpdater = core.lib.mkUpdater { inherit (pkgs) lib; };
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
            # corepkgs' own machinery packages (formatelf, wrapBuddy,
            # buildNpmPackage, versionCheckHomeHook), callPackage'd into the same
            # scope so consuming nixpkgs packages resolve them by argument name.
            # corepkgs owns their location; we just call the functions it exposes.
            // lib.mapAttrs (_name: fn: self.callPackage fn { }) core.machinery
          );

          # Generate a standard passthru.updateScript from a package's
          # declarative passthru.updater config (see lib/mk-update-script.nix).
          mkUpdateScript = core.lib.mkUpdateScript {
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
              let
                updateScript = mkUpdateScript {
                  inherit name;
                  config = pkg.updater;
                };
              in
              # nixpkgs packages get updateScript via overrideAttrs (lifts it
              # top-level). corepkgs (naked) derivations have no overrideAttrs, so
              # attach it directly - metadata only, no rebuild.
              if pkg ? overrideAttrs then
                pkg.overrideAttrs (old: {
                  passthru = (old.passthru or { }) // {
                    inherit updateScript;
                  };
                })
              else
                pkg
                // {
                  inherit updateScript;
                  passthru = (pkg.passthru or { }) // {
                    inherit updateScript;
                  };
                }
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
      lib = coreApi.flakeLib { inherit inputs; };

      inherit packages devShells;

      overlays.shared-nixpkgs = import ./overlays/shared-nixpkgs.nix {
        inherit mkPackagesFor;
      };

      formatter = eachSystem (system: allPackages.${system}.formatter);

      checks = eachSystem (
        system:
        let
          core = import ./corepkgs {
            inherit system;
            pkgs = pkgsFor.${system};
          };
          # FHS guard for every corepkgs package (it carries a `.fhs` passthru):
          # assert the output is store-only, no ELF left on a host loader.
          # ELF-only, so Linux systems only. Replaces the per-spike checks the
          # swap removed.
          fhsChecks = lib.optionalAttrs (lib.hasSuffix "-linux" system) (
            lib.mapAttrs' (
              name: pkg:
              lib.nameValuePair "fhs-${name}" (
                core.lib.checkFhs {
                  package = pkg;
                  inherit name;
                }
              )
            ) (lib.filterAttrs (_name: pkg: pkg ? fhs) packages.${system})
          );
        in
        lib.mapAttrs' (name: pkg: lib.nameValuePair "pkgs-${name}" pkg) packages.${system}
        // lib.genAttrs checkNames (
          name:
          callWith {
            pkgs = pkgsFor.${system};
            inherit flake inputs system;
            inherit (core.lib) interpolate;
          } (import (./checks + "/${name}.nix"))
        )
        // {
          devshell-default = devShells.${system}.default;
        }
        // fhsChecks
        # corepkgs' own machinery (seed + toolchains + formatelf + hello),
        # exposed as checks.<system>.core-* so nixbot builds it.
        // lib.mapAttrs' (name: v: lib.nameValuePair "core-${name}" v) core.packages
      );
    };
}
