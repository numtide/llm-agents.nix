# sandbox-runtime (srt) - built on corepkgs (nixpkgs-free) via mkNpm. Prebuilt
# registry tarball (dontNpmBuild); node_modules vendored from the committed lock.
# Ships a prebuilt native addon (@unrs/resolver-binding), so nativeAddons=true
# patchelfs it to the pinned glibc - keeps it store-only.
#
# NOTE: at runtime srt needs bubblewrap + socat + ripgrep on PATH (the nixpkgs
# recipe suffixes them via wrapProgram). corepkgs has no runtime-PATH mechanism
# yet, so for now they must be present in the environment.
{
  mkNpm,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkNpm {
  pname = "sandbox-runtime";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/sandbox-runtime/-/sandbox-runtime-${data.version}.tgz";
    inherit (data) hash;
  };
  packageLock = ./package-lock.json;
  npmDepsHash = data.npmDepsHash;
  buildScript = "";
  nativeAddons = true;
  mainProgram = "srt";
  category = "Sandboxing & Isolation";
  meta = {
    description = "Lightweight sandboxing tool for enforcing filesystem and network restrictions";
    homepage = "https://github.com/anthropic-experimental/sandbox-runtime";
    changelog = "https://github.com/anthropic-experimental/sandbox-runtime/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ ];
  };
}
