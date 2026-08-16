# workmux - built from source on corepkgs (nixpkgs-free) via mkCargo. Pure
# crates.io except one git dependency (an upstream crossterm fork), vendored via
# gitDeps (the github archive at the locked rev, wired as a cargo source
# replacement). No C libraries.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "workmux";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/raine/workmux/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "workmux" ];
  gitDeps = [
    {
      crate = "crossterm";
      source = "git+https://github.com/raine/crossterm#f99eeae405e28fa8cb353a6c6e36c493e72891bd";
      hash = data.crosstermHash;
    }
  ];

  category = "Workflow & Project Management";
  meta = {
    description = "Git worktrees + tmux windows for zero-friction parallel dev";
    homepage = "https://github.com/raine/workmux";
    changelog = "https://github.com/raine/workmux/blob/v${data.version}/CHANGELOG.md";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ ];
  };
}
