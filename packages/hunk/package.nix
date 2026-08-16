# hunk - built from source on corepkgs (nixpkgs-free) via mkBun (ported off
# bun2nix, which dragged pandoc/GHC in through its yq-go build hook). Pure-JS bun
# TUI; mkBun installs the app + vendored node_modules under $out/lib/hunk and
# wraps `bun run src/main.tsx` on the naked bun toolchain (no --compile). The
# bundled review skill is found via import.meta.dir ancestor walk
# (src/core/paths.ts resolveBundledHunkReviewSkillPath), which the installed
# $out/lib/hunk/skills tree satisfies.
{
  mkBun,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkBun {
  pname = "hunk";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/modem-dev/hunk/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  bunDepsHash = data.bunDepsHash;
  entry = "src/main.tsx";

  category = "Code Review";
  meta = {
    description = "Terminal diff viewer for agentic changesets";
    homepage = "https://github.com/modem-dev/hunk";
    changelog = "https://github.com/modem-dev/hunk/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.benvinegar ];
  };
}
