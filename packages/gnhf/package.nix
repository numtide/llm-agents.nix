# gnhf - built from source on corepkgs (nixpkgs-free) via mkPnpm. pnpm deps
# vendored as a flat hoisted node_modules FOD; `pnpm run build` (tsdown) produces
# dist, and mkPnpm wraps `node dist/cli.mjs` on the naked node toolchain.
{
  mkPnpm,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPnpm {
  pname = "gnhf";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/kunchenguid/gnhf/archive/refs/tags/gnhf-v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pnpmDepsHash = data.pnpmDepsHash;
  entry = "dist/cli.mjs";

  category = "Workflow & Project Management";
  meta = {
    description = "Ralph/autoresearch-style orchestrator that keeps coding agents running while you sleep";
    homepage = "https://github.com/kunchenguid/gnhf";
    changelog = "https://github.com/kunchenguid/gnhf/releases/tag/gnhf-v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ pikdum ];
  };
}
