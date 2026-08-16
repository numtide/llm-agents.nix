# nixfmt-rs - the Rust port of nixfmt (RFC 166), built from source on corepkgs
# (nixpkgs-free) via mkCargo. Byte-identical output to nixfmt 1.4.0; this repo's
# formatter uses it. Pure crates.io deps; mimalloc's bundled C compiles via zig cc.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "nixfmt-rs";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/Mic92/nixfmt-rs/archive/refs/tags/${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "nixfmt" ];
  hideFromDocs = true;

  meta = {
    description = "The official Nix formatter (RFC 166), Rust port";
    homepage = "https://github.com/Mic92/nixfmt-rs";
    changelog = "https://github.com/Mic92/nixfmt-rs/releases/tag/${data.version}";
    license = flake.lib.licenses.mpl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.mic92 ];
    # mkCargo has a darwin path now; the Nix formatter is wanted on darwin too.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
