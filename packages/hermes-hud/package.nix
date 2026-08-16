# hermes-hud - built from source on corepkgs (nixpkgs-free) via mkPython. pip
# builds the setuptools project into a site tree and resolves the runtime closure
# (pyyaml/textual/pyfiglet, all pure-python) from PyPI.
{
  mkPython,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPython {
  pname = "hermes-hud";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/joeynyc/hermes-hud/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pythonDepsHash = data.pythonDepsHash;
  entrypoints.hermes-hud = "hermes_hud.hud:main";

  category = "AI Assistants";
  meta = {
    description = "TUI consciousness monitor for Hermes Agent";
    homepage = "https://github.com/joeynyc/hermes-hud";
    changelog = "https://github.com/joeynyc/hermes-hud/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.smdex ];
  };
}
