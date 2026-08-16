# git-surgeon - built from source on corepkgs (nixpkgs-free): mkCargo drives the
# naked rust toolchain + zig cc + cargo-vendor'd crates. Pure crates.io deps, no
# C libraries. version + src hash live in ./hashes.json (the file nix-update
# bumps); the Cargo.lock is vendored alongside (the nixpkgs-free cargoHash).
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "git-surgeon";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/raine/git-surgeon/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "git-surgeon" ];

  category = "Utilities";
  meta = {
    description = "Git primitives for autonomous coding agents";
    homepage = "https://github.com/raine/git-surgeon";
    changelog = "https://github.com/raine/git-surgeon/blob/v${data.version}/CHANGELOG.md";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.sei40kr ];
  };
}
