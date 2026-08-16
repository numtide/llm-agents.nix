# Validate a declarative `passthru.updater` config, so a malformed one fails
# `nix flake check` instead of the next weekly update run. Consumed as data
# (nix eval --json) by scripts/updater/run.py.
_scope:
{ lib }:
let
  requiredByKind = {
    # flakeAttr is injected from the package name by mk-update-script.nix, not
    # a required config field here.
    "github-source" = [
      "purl"
      "depHashKey"
    ];
    "npm" = [ "purl" ];
    "bun-github" = [ "purl" ];
    "platform" = [
      "versionSource"
      "urlTemplate"
      "platforms"
    ];
    "manifest" = [
      "manifestUrl"
      "platformMap"
    ];
    "manifest-checksums" = [
      "versionSource"
      "manifestUrl"
      "checksumPath"
      "platforms"
    ];
  };
in
config:
let
  kind = config.kind or (throw "passthru.updater: missing required attribute 'kind'");
  required =
    requiredByKind.${kind} or (throw (
      "passthru.updater: unknown kind '${kind}' (known: "
      + lib.concatStringsSep ", " (lib.attrNames requiredByKind)
      + ")"
    ));
  missing = lib.filter (field: !(config ? ${field})) required;
in
if missing != [ ] then
  throw "passthru.updater (kind '${kind}'): missing ${lib.concatStringsSep ", " missing}"
else
  config
