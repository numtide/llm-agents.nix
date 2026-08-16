# apm - built from source on corepkgs (nixpkgs-free) via mkPython. pip builds the
# setuptools project into a site tree and resolves the runtime closure (llm +
# llm-github-models + azure-ai-inference and their pure-python/manylinux deps)
# from PyPI; mkPython wraps the console script.
{
  mkPython,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPython {
  pname = "apm";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/microsoft/apm/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pythonDepsHash = data.pythonDepsHash;
  entrypoints.apm = "apm_cli.cli:main";

  category = "Utilities";
  meta = {
    description = "Agent Package Manager — dependency manager for AI agents";
    homepage = "https://github.com/microsoft/apm";
    changelog = "https://github.com/microsoft/apm/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
  };
}
