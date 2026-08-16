# shuck: a fast shell linter + formatter (+ LSP) in Rust - the treefmt shell tool
# (replaces shellcheck + shfmt). Built from source on corepkgs (nixpkgs-free) via
# mkCargo: naked rust + zig cc, per-crate crates.io FODs from Cargo.lock. Build
# only the CLI crate (`-p shuck-cli`, bin `shuck`); the workspace's shuck-
# benchmark member (the sole jemalloc user, which needs autotools) is skipped.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "shuck";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/ewhauser/shuck/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  cargoBuildFlags = [
    "-p"
    "shuck-cli"
  ];
  binaries = [ "shuck" ];
  hideFromDocs = true;

  meta = {
    description = "Fast shell script linter and formatter written in Rust";
    homepage = "https://github.com/ewhauser/shuck";
    changelog = "https://github.com/ewhauser/shuck/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ ];
    mainProgram = "shuck";
    # mkCargo now has a darwin path (zig cc -> Mach-O); claim all four so CI
    # builds + validates it there. It's the formatter shell tool, wanted on darwin.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
