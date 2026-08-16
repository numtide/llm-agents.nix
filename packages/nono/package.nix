# nono - built from source on corepkgs (nixpkgs-free) via mkCargo. The workspace
# is at the tarball root; we build the nono-cli crate (-p nono-cli) which emits
# the `nono` binary. On Linux the keyring backend is async-secret-service with
# crypto-rust, i.e. pure-Rust zbus - no system libdbus. `ring` bundles its own C
# and compiles it through the `cc` crate (our `zig cc` wrapper). Pure crates.io,
# no git deps. The nixpkgs if-let-guard patch and the MSRV-unpin hook are dropped:
# rust 1.97.1 supports if-let guards and clears the rust-version = "1.95" floor.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "nono";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/always-further/nono/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  cargoBuildFlags = [
    "-p"
    "nono-cli"
  ];
  binaries = [ "nono" ];

  category = "Sandboxing & Isolation";
  meta = {
    description = "Kernel-enforced agent sandbox. Capability-based isolation with secure key management, atomic rollback, cryptographic immutable audit chain of provenance. Run your agents in a zero-trust environment.";
    homepage = "https://nono.sh/";
    changelog = "https://github.com/always-further/nono/releases/tag/v${data.version}";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.pogobanane ];
  };
}
