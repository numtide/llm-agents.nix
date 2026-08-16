# fetchurl with a templated URL. Shared by a package's build and its declarative
# updater, so the two can never fetch different URLs. Extra args pass through.
scope:
{
  urlTemplate,
  vars,
  ...
}@args:
let
  inherit (scope) fetchurl interpolate;
in
fetchurl (
  (builtins.removeAttrs args [
    "urlTemplate"
    "vars"
  ])
  // {
    url = interpolate urlTemplate vars;
  }
)
