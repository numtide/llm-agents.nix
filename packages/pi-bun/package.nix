{
  lib,
  buildNpmPackage,
  bun,
  makeWrapper,
  nodejs,
  fetchurl,
  fd,
  ripgrep,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

(import ../pi/package.nix {
  inherit
    lib
    buildNpmPackage
    bun
    makeWrapper
    nodejs
    fetchurl
    fd
    ripgrep
    runCommand
    versionCheckHook
    versionCheckHomeHook
    ;

  runtime = "bun";
  pname = "pi-bun";
  description = "Pi coding agent with Bun runtime support";
  longDescription = ''
    A variant of the Pi coding agent that starts the upstream Bun-specific
    entry point with the Bun JavaScript runtime. It shares the same source,
    lockfile, dependency hash, and updater as the default pi package; only the
    runtime wrapper differs.
  '';
})
