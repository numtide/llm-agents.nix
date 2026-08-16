# toon - built from source on corepkgs (nixpkgs-free) via mkCargo. Pure crates.io
# deps, no C libraries; the "cli" feature pulls the toon binary. Source is the
# published crate tarball from crates.io (not a GitHub archive).
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "toon-format";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://static.crates.io/crates/toon-format/toon-format-${data.version}.crate";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "toon" ];
  cargoBuildFlags = [
    "--features"
    "cli"
  ];

  category = "Utilities";
  meta = {
    description = "Rust implementation of TOON - Token-Oriented Object Notation for LLM prompts";
    homepage = "https://github.com/toon-format/toon-rust";
    changelog = "https://github.com/toon-format/toon-rust/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.antono ];
  };
}
