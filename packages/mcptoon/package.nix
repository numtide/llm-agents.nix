# mcptoon - built from source on corepkgs (nixpkgs-free) via mkPython. Zero
# runtime deps; pip builds the setuptools project into a site tree and mkPython
# wraps the console entry point on the naked CPython toolchain.
{
  mkPython,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPython {
  pname = "mcptoon";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/activeing123/mcptoon/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pythonDepsHash = data.pythonDepsHash;
  entrypoints.mcptoon = "mcptoon.cli:main";
  # upstream tags without bumping __version__; the CLI banner prints it.
  postPatch = ''sed -i -E 's/^__version__ = ".*"/__version__ = "${data.version}"/' src/mcptoon/__init__.py'';

  category = "Utilities";
  meta = {
    description = "Token-efficient MCP CLI client that converts tool discovery and results to compact TOON output";
    homepage = "https://github.com/activeing123/mcptoon";
    changelog = "https://github.com/activeing123/mcptoon/releases/tag/v${data.version}";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.zimbatm ];
  };
}
