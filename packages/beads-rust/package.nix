# beads-rust (br) - built from source on corepkgs (nixpkgs-free) via mkCargo.
# Pure crates.io deps (the published fsqlite-* crates resolve from crates.io with
# checksums). fsqlite uses #![feature(...)] gated to nightly, so RUSTC_BOOTSTRAP=1
# enables those on the stable toolchain (same as the nixpkgs recipe).
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "beads-rust";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/Dicklesworthstone/beads_rust/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "br" ];
  mainProgram = "br";
  # self_update feature makes no sense under Nix; drop it (nixpkgs does the same).
  cargoBuildFlags = [ "--no-default-features" ];
  extraEnv.RUSTC_BOOTSTRAP = "1";

  category = "Workflow & Project Management";
  meta = {
    description = "Fast Rust port of beads - a local-first issue tracker for git repositories";
    homepage = "https://github.com/Dicklesworthstone/beads_rust";
    changelog = "https://github.com/Dicklesworthstone/beads_rust/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.afterthought ];
  };
}
