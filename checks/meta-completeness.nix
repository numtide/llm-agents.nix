# Enforce the metadata every user-facing package MUST declare (AGENTS.md).
#
# meta.maintainers is covered by meta-maintainers.nix; this check guards the
# remaining required attributes that Nix evaluation alone won't reject:
# meta.changelog, meta.mainProgram, meta.sourceProvenance, and
# passthru.category.  Internal helpers/aliases opt out via
# passthru.hideFromDocs (the same flag the README generator uses).
#
# The update workflow only discovers packages with a `version`, so one
# without it silently stops being updated; passthru.skipUpdate opts out.
{
  pkgs,
  flake,
  system,
  ...
}:

let
  inherit (pkgs) lib;

  packages = flake.packages.${system} or { };

  checkPackage =
    name: pkg:
    let
      hidden = pkg.passthru.hideFromDocs or false;
      missing = lib.optionals (!hidden) (
        lib.optional (!(pkg.meta ? changelog)) "meta.changelog"
        ++ lib.optional (!(pkg.meta ? mainProgram)) "meta.mainProgram"
        ++ lib.optional ((pkg.meta.sourceProvenance or [ ]) == [ ]) "meta.sourceProvenance"
        ++ lib.optional (!(pkg.passthru ? category)) "passthru.category"
        ++ lib.optional (!(pkg ? version) && !(pkg.passthru.skipUpdate or false)) "version"
      );
    in
    lib.optional (missing != [ ]) "${name}: missing ${lib.concatStringsSep ", " missing}";

  problems = lib.concatLists (lib.mapAttrsToList checkPackage packages);
in
if problems != [ ] then
  throw ("Incomplete package metadata:\n" + lib.concatStringsSep "\n" problems)
else
  pkgs.runCommand "meta-completeness-check" { } ''
    echo "All package metadata complete"
    touch $out
  ''
