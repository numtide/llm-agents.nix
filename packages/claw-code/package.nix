# claw-code - built from source on corepkgs (nixpkgs-free) via mkCargo. Workspace
# in rust/ (sourceRoot); the `claw` binary is the rusty-claude-cli crate. Tracks
# an unstable upstream rev (no tagged release yet).
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "claw-code";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/ultraworkers/claw-code/archive/b71afddae100ced324457337925a694686b8fef2.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  sourceRoot = "rust";
  cargoBuildFlags = [
    "-p"
    "rusty-claude-cli"
  ];
  binaries = [ "claw" ];

  category = "AI Coding Agents";
  meta = {
    description = "Claude Code rewrite CLI built from the official claw-code Rust workspace";
    homepage = "https://github.com/ultraworkers/claw-code";
    changelog = "https://github.com/ultraworkers/claw-code/commits/main";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ ];
  };
}
