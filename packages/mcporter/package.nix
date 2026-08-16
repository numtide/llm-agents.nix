# mcporter - built from source on corepkgs (nixpkgs-free) via mkPnpm. pnpm deps
# vendored as a flat hoisted node_modules FOD; `pnpm run build` (tsc) produces
# dist, and mkPnpm wraps `node dist/cli.js` on the naked node toolchain.
{
  mkPnpm,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPnpm {
  pname = "mcporter";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/openclaw/mcporter/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  pnpmDepsHash = data.pnpmDepsHash;
  entry = "dist/cli.js";
  # upstream's lockfile predates the pnpm.overrides vite entry; align the
  # specifier so pnpm accepts the frozen lockfile.
  postPatch = ''sed -i 's/specifier: \^8\.0\.8/specifier: 8.0.8/' pnpm-lock.yaml'';

  category = "Utilities";
  meta = {
    description = "TypeScript runtime and CLI for the Model Context Protocol";
    homepage = "https://github.com/openclaw/mcporter";
    changelog = "https://github.com/openclaw/mcporter/releases";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ ];
  };
}
