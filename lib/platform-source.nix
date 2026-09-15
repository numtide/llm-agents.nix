# Select the prebuilt release artifact for the host platform from a package's
# hashes.json. Returns both the build `src` and a matching `updater` fragment
# from the same urlTemplate + platform map, so build and updater never diverge
# (see scripts/updater/run.py, kind = "platform").
{
  lib,
  stdenv,
  fetchurlTemplate,
}:
let
  versionVars = import ./version-vars.nix { inherit lib; };
in

{
  hashesFile, # { version, hashes.<system> }
  # nix system -> URL vars. String is shorthand for the {platform} var; an
  # attrset supplies arbitrary vars (e.g. { os = "linux"; cpu = "x86_64"; }).
  platforms,
  urlTemplate,
}:

let
  versionData = builtins.fromJSON (builtins.readFile hashesFile);
  inherit (versionData) version;
  system = stdenv.hostPlatform.system;
  entry = platforms.${system} or (throw "Unsupported system: ${system}");
  platformVars = if builtins.isAttrs entry then entry else { platform = entry; };
in
{
  inherit version;
  platforms = builtins.attrNames platforms;
  src = fetchurlTemplate {
    inherit urlTemplate;
    vars = versionVars version // platformVars;
    hash = versionData.hashes.${system};
  };
  # Ready-to-merge passthru.updater fragment; caller adds a versionSource.
  updater = {
    kind = "platform";
    inherit urlTemplate platforms;
  };
}
