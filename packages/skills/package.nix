# skills - built on corepkgs (nixpkgs-free) via mkNpm. Prebuilt registry tarball
# (dontNpmBuild); node_modules vendored from the committed lock. Ships prebuilt
# native addons (@rolldown/binding, lightningcss), so nativeAddons=true patchelfs
# them to the pinned glibc (the autoPatchelfHook equivalent) - keeps it store-only.
{
  mkNpm,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkNpm {
  pname = "skills";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://registry.npmjs.org/skills/-/skills-${data.version}.tgz";
    inherit (data) hash;
  };
  packageLock = ./package-lock.json;
  npmDepsHash = data.npmDepsHash;
  buildScript = "";
  nativeAddons = true;
  category = "Skills & Plugins";
  meta = {
    description = "The open agent skills tool for installing and managing skills across AI coding agents";
    homepage = "https://github.com/vercel-labs/skills";
    changelog = "https://github.com/vercel-labs/skills/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ kusold ];
  };
}
