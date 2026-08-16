# cc-sdd - built from source on corepkgs (nixpkgs-free) via mkNpm. TypeScript CLI
# (npm run build -> tsc -> dist/cli.js). Deps vendored as a node_modules FOD.
{
  mkNpm,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkNpm {
  pname = "cc-sdd";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/gotalab/cc-sdd/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  npmDepsHash = data.npmDepsHash;
  sourceRoot = "tools/cc-sdd";
  category = "Workflow & Project Management";
  meta = {
    description = "Bring spec-driven development to Claude Code, Cursor, Gemini CLI and other AI coding agents";
    homepage = "https://github.com/gotalab/cc-sdd";
    changelog = "https://github.com/gotalab/cc-sdd/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.ryoppippi ];
  };
}
