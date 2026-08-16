# ralph-tui - built from source on corepkgs (nixpkgs-free) via mkBun. The upstream
# `bun run build` bundles src/cli.tsx -> dist/cli.js (externalizing @opentui/* and
# react, which stay in the vendored node_modules) and copies assets/skills/templates.
# mkBun then wraps `bun run dist/cli.js` on the naked bun toolchain (no --compile,
# which @opentui/core's top-level-await FFI could not use anyway).
{
  mkBun,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkBun {
  pname = "ralph-tui";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/subsy/ralph-tui/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  bunDepsHash = data.bunDepsHash;
  buildScript = "run build";
  entry = "dist/cli.js";

  category = "Workflow & Project Management";
  meta = {
    description = "AI Agent Loop Orchestrator TUI";
    homepage = "https://github.com/subsy/ralph-tui";
    changelog = "https://github.com/subsy/ralph-tui/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.afterthought ];
  };
}
