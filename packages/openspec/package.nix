# openspec - built on corepkgs (nixpkgs-free) via mkNpm. Prebuilt-dist npm
# package (registry tgz, dontNpmBuild); node_modules vendored from the committed
# package-lock.json (the tgz ships none, so inject it - like the nixpkgs recipe).
{
  mkNpm,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkNpm {
  pname = "openspec";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://registry.npmjs.org/@fission-ai/openspec/-/openspec-${data.version}.tgz";
    inherit (data) hash;
  };
  packageLock = ./package-lock.json;
  npmDepsHash = data.npmDepsHash;
  buildScript = "";
  category = "Workflow & Project Management";
  meta = {
    description = "Spec-driven development for AI coding assistants";
    homepage = "https://github.com/Fission-AI/OpenSpec";
    changelog = "https://github.com/Fission-AI/OpenSpec/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.binaryBytecode ];
    maintainers = [ ];
  };
}
