# ax - built from source on corepkgs (nixpkgs-free) via mkBun. Pure-JS bun CLI;
# mkBun installs the app + vendored node_modules under $out/lib/ax and wraps
# `bun run src/index.ts` on the naked bun toolchain (no --compile needed).
{
  mkBun,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkBun {
  pname = "ax";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/yusukebe/ax/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  bunDepsHash = data.bunDepsHash;
  entry = "src/index.ts";

  category = "Utilities";
  meta = {
    description = "The AI-era curl: fetch, discover, extract. One command";
    homepage = "https://github.com/yusukebe/ax";
    changelog = "https://github.com/yusukebe/ax/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.ryoppippi ];
  };
}
