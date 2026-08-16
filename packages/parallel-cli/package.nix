# parallel-cli - built from source on corepkgs (nixpkgs-free) via mkPython. pip
# builds the hatchling project into a site tree and resolves the base runtime
# closure (parallel-web + manylinux/pure-python deps) from PyPI; mkPython wraps
# the console script. The optional data-integration extras (polars, duckdb,
# snowflake, bigquery) are not installed by the base `pip install .`.
{
  mkPython,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPython {
  pname = "parallel-cli";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/parallel-web/parallel-web-tools/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pythonDepsHash = data.pythonDepsHash;
  entrypoints.parallel-cli = "parallel_web_tools.cli:main";

  category = "Utilities";
  meta = {
    description = "AI-powered web search, extraction, and research CLI from Parallel";
    homepage = "https://github.com/parallel-web/parallel-web-tools";
    changelog = "https://github.com/parallel-web/parallel-web-tools/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.SecBear ];
  };
}
