# Vendor a Cargo.lock's crates.io deps: each .crate is one builtin:fetchurl FOD
# keyed by the sha256 straight from Cargo.lock. Assemble the cargo vendor dir
# with a .cargo-checksum.json per crate.
scope:
let
  inherit (scope) mkDrvSh;

  fetchCrate =
    {
      name,
      version,
      sha256hex,
    }:
    let
      url = "https://static.crates.io/crates/${name}/${name}-${version}.crate";
    in
    derivation {
      inherit url;
      name = "${name}-${version}.crate";
      builder = "builtin:fetchurl";
      system = "builtin";
      urls = [ url ];
      outputHashAlgo = "sha256";
      outputHashMode = "flat";
      outputHash = sha256hex; # hex, straight from Cargo.lock
      unpack = false;
      executable = false;
      preferLocalBuild = true;
    };
in
{
  cargoLock,
  # git deps: [{ crate = "<name>"; archive = <fetched github archive tarball>; }].
  # cargo vendors a git dep under a plain <crate>/ dir with a null-package
  # checksum; source-replacement wiring lives in mk/cargo's builder.sh config.toml.
  gitDeps ? [ ],
}:
let
  lock = builtins.fromTOML (builtins.readFile cargoLock);
  crates = builtins.filter (p: p ? checksum) lock.package;
  line =
    p:
    "${p.name} ${p.version} ${p.checksum} ${
      fetchCrate {
        inherit (p) name version;
        sha256hex = p.checksum;
      }
    }";
  manifest = builtins.concatStringsSep "\n" (map line crates);
  gitManifest = builtins.concatStringsSep "\n" (map (g: "${g.crate} ${g.archive}") gitDeps);
in
mkDrvSh {
  name = "cargo-vendor";
  env = { inherit manifest gitManifest; };
  script = ./builder.sh;
}
