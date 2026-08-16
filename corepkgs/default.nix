# corepkgs — the nixpkgs-free packaging system, as an importable API.
#
#   core = import ./corepkgs { inherit system; }
#   core.lib.mkPackage { ... }   # the builder API
#   core.packages               # own buildable outputs (-bin toolchains + hello)
#
# Internally every module is wired through one memoized tree (scope.nix +
# registry.nix): a module names its deps with `inherit (scope) ...` instead of
# path-importing a sibling. This file is a thin view over that scope. `pins` and
# `toolchains` are the two swappable providers (the bootstrap seam); swap either
# for a from-source bootstrap without touching a constructor.
{
  system ? builtins.currentSystem,
  pkgs ? null,
  # Pins from `pkgs` when given (root flake reuses its nixpkgs); otherwise the
  # nixpkgs-free provider that makes corepkgs a standalone no-input flake.
  # Default nixpkgs-free backend is rehydrated.nix: a serialized .drv closure
  # replayed in pure Nix, so pins stay buildable from source on a cache-GC miss
  # (it falls through to closure.nix for formatelf and non-x86_64-linux systems).
  # closure.nix (appendContext store paths) and store.nix (impure fast-eval) are
  # the other two backends behind this seam.
  pins ? if pkgs != null then import ./pins/pkgs.nix pkgs else import ./pins/rehydrated.nix system,
  # null => the registry's toolchain provider (derived from the -bin packages);
  # pass one to override (bootstrap seam).
  toolchains ? null,
}:
let
  scope = import ./scope.nix { inherit system pins toolchains; };

  # smoke test: a nixpkgs-free derivation with no toolchain at all.
  hello = scope.mkDrvNu {
    name = "hello";
    script = ''
      mkdir $"($out)/bin"
      "#!/bin/sh\necho hello from a nixpkgs-free derivation\n" | save --raw $"($out)/bin/hello"
      ^chmod +x $"($out)/bin/hello"
    '';
  };

  # Machinery packages (formatelf, wrapBuddy, buildNpmPackage,
  # versionCheckHomeHook, nixfmt-rs): by-name package FUNCTIONS, un-called - the
  # consumer callPackage's them into its OWN scope. Exclude the `-bin` toolchain
  # packages: they are scope modules mapped by the toolchains provider, not a
  # consumer callPackage scope.
  machinery =
    let
      entries = builtins.readDir ./packages;
      dirs = builtins.filter (n: entries.${n} == "directory" && builtins.match ".*-bin" n == null) (
        builtins.attrNames entries
      );
    in
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = import (./packages + "/${n}/package.nix");
      }) dirs
    );
in
{
  inherit system machinery;
  inherit (scope) pins toolchains;

  # The builder API: constructors + owned primitives. Each is already bound to
  # the scope (system/pins/toolchains inside), so a consumer's package.nix stays
  # terse - just `mkPackage { ... }`.
  lib = {
    inherit (scope)
      mkPackage
      mkCargo
      mkGo
      mkNpm
      mkBun
      mkPnpm
      mkPython
      mkDrvNu
      mkDrvSh
      checkFhs
      interpolate
      fetchurlTemplate
      platformSource
      seed
      systems
      pins
      system
      # Meta helpers, un-called so the consumer supplies its own nixpkgs deps but
      # never path-imports a corepkgs file.
      mkUpdater
      mkUpdateScript
      flakeLib
      ;
    coreFetchurl = scope.fetchurl;
  };

  # Own buildable outputs: seed + -bin toolchains + hello (the -bin suffix marks
  # the prebuilt toolchain binaries; the provider maps them to logical names).
  # python is x86_64-linux only (manylinux lib pins). Linux only: systems.nix
  # carries no darwin toolchain rows (darwin has just the nushell seed).
  packages =
    if system == "x86_64-linux" || system == "aarch64-linux" then
      {
        inherit (scope.toolchains) seed;
        bun-bin = scope.toolchains.bun;
        node-bin = scope.toolchains.node;
        zig-bin = scope.toolchains.zig;
        go-bin = scope.toolchains.go;
        rust-bin = scope.toolchains.rust;
        pnpm-bin = scope.toolchains.pnpm;
        inherit hello;
      }
      // (if system == "x86_64-linux" then { python-bin = scope.toolchains.python; } else { })
    else
      { };
}
