# tuicr - built from source on corepkgs (nixpkgs-free) via mkCargo. Uses git2,
# whose libgit2-sys bundles and compiles its own libgit2 C through the `cc` crate
# (our `zig cc` wrapper as $CC) when no system libgit2 is found - so no external
# C libraries. Pure crates.io, no git deps.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "tuicr";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/agavra/tuicr/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "tuicr" ];

  category = "Code Review";
  meta = {
    description = "Review AI-generated diffs like a GitHub pull request, right from your terminal";
    homepage = "https://github.com/agavra/tuicr";
    changelog = "https://github.com/agavra/tuicr/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.ypares ];
  };
}
