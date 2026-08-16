# terminal-use - built from source on corepkgs (nixpkgs-free) via mkCargo. Pure
# crates.io deps; installs the `tu` binary. Upstream ships a placeholder 0.0.0
# manifest version that its release workflow rewrites at tag time, so `tu
# --version` reports 0.0.0 here (we do not run the substituteInPlace tweak).
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "terminal-use";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/flipbit03/terminal-use/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  # `tu self update` rewrites its own binary / shells out to cargo install, which
  # is wrong for a read-only Nix store; the patch makes it refuse.
  patches = [ ./disable-self-update.patch ];
  binaries = [ "tu" ];

  category = "Utilities";
  meta = {
    description = "Headless virtual terminal for AI agents";
    longDescription = ''
      tu is a full terminal emulator for AI agents. It spawns interactive
      terminal apps and lets an agent read the rendered screen (as text or PNG
      screenshot) and drive the keyboard and mouse — no GUI, X server, or
      display needed. Multiple sessions can run at once, like tmux for an
      agent.
    '';
    homepage = "https://github.com/flipbit03/terminal-use";
    changelog = "https://github.com/flipbit03/terminal-use/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    mainProgram = "tu";
    maintainers = [ flake.lib.maintainers.mic92 ];
  };
}
