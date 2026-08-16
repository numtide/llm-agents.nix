{ pkgs }:
# nixpkgs' buildNpmPackage with an eval-time guard.
#
# Our npm packages set `npmDepsFetcherVersion = 2`; their committed npmDepsHash
# depends on it. Pre-support nixpkgs silently ignores the attr and falls back to
# v1, surfacing only as a confusing FOD hash mismatch on -npm-deps.drv (#4320).
# The guard fires on every path that swaps nixpkgs (the scope is built against
# whatever `pkgs` is in effect).
let
  inherit (pkgs) lib;
  hasFetcherVersion = (lib.functionArgs pkgs.fetchNpmDeps) ? fetcherVersion;
  msg = ''
    llm-agents.nix: this nixpkgs is too old for our npm packages.

    fetchNpmDeps lacks the `fetcherVersion` argument, so the committed
    npmDepsHash (computed with fetcherVersion = 2) cannot match. You are
    likely on nixos-25.11 or an early-2026 unstable via
    `overlays.shared-nixpkgs` or `inputs.llm-agents.inputs.nixpkgs.follows`.

    Either use the flake packages directly, or bump nixpkgs to at least
    203662a570c4 (2026-02-15). See
    https://github.com/numtide/llm-agents.nix/issues/4320.
  '';
in
# A real (empty) derivation so blueprint / buildbot can enumerate and "build" it;
# the __functor forwards to the real builder so `buildNpmPackage { … }` works.
pkgs.emptyDirectory.overrideAttrs { name = "buildNpmPackage-guard"; }
// {
  __functor =
    _:
    assert lib.assertMsg hasFetcherVersion msg;
    # the use-perSystem-buildNpmPackage rule is scoped to packages/**; this is the
    # one sanctioned pkgs.buildNpmPackage use, so no suppression is needed here.
    pkgs.buildNpmPackage;
  override = pkgs.buildNpmPackage.override;
  passthru.hideFromDocs = true;
  meta = {
    description = "nixpkgs buildNpmPackage with an eval guard for fetcherVersion=2";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
