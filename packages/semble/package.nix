# semble - built from source on corepkgs (nixpkgs-free) via mkPython. pip builds
# the setuptools_scm project into a site tree and resolves the whole runtime
# closure from PyPI: model2vec, vicinity, semble-grammars (a prebuilt tree-sitter
# manylinux wheel), numpy, tokenizers/safetensors (rust manylinux wheels), plus
# the mcp extra. mkPython wraps the console entry point.
{
  mkPython,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPython {
  pname = "semble";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/MinishLab/semble/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pythonDepsHash = data.pythonDepsHash;

  # Upstream's `semble` entry auto-dispatches to the CLI or the MCP server based
  # on argv; `semble-mcp` is the same entry, exposed as a stable name for wiring
  # into agent configs.
  entrypoints.semble = "semble.cli:main";
  entrypoints."semble-mcp" = "semble.cli:main";
  mainProgram = "semble";

  # Two load-bearing source fixups before pip install:
  #  1. setuptools_scm derives the version from git, which the source tarball
  #     lacks; pin it so the build does not fall back to 0.0.0+unknown (which
  #     would also break the `attr = semble.version.__version__` resolver).
  #  2. Fold the [mcp] extra into the base dependencies so `semble-mcp` works
  #     (mkPython installs `.`, not `.[mcp]`).
  postPatch = ''
    export SETUPTOOLS_SCM_PRETEND_VERSION=${data.version}
    sed -i 's|"semble-grammars>=0.1.2",|"semble-grammars>=0.1.2", "mcp>=1.0,<2.0",|' pyproject.toml
  '';

  category = "Memory & Code Intelligence";
  meta = {
    description = "Fast and accurate local code search for AI agents — CLI and MCP server";
    homepage = "https://github.com/MinishLab/semble";
    changelog = "https://github.com/MinishLab/semble/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.murlakatam ];
  };
}
