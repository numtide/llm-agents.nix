# Template vars derived from a version: {version} and {versionEnc}. Must stay
# in lockstep with version_vars in scripts/updater/interpolate.py.
{ lib }:
version: {
  inherit version;
  versionEnc = lib.strings.escapeURL version;
}
