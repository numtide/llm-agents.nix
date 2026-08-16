# spec-kit - built from source on corepkgs (nixpkgs-free) via mkPython. pip
# builds the hatchling project into a site tree and resolves the runtime closure
# (typer/rich/httpx/... all pure-python or manylinux wheels) from PyPI.
{
  mkPython,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPython {
  pname = "spec-kit";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/github/spec-kit/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pythonDepsHash = data.pythonDepsHash;
  entrypoints.specify = "specify_cli:main";
  mainProgram = "specify";

  category = "Workflow & Project Management";
  meta = {
    description = "Specify CLI, part of GitHub Spec Kit. A tool to bootstrap your projects for Spec-Driven Development (SDD)";
    homepage = "https://github.com/github/spec-kit";
    changelog = "https://github.com/github/spec-kit/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
  };
}
