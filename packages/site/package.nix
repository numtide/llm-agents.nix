{
  lib,
  stdenvNoCC,
  jq,
  allPackages,
}:

let
  formatLicense =
    l:
    if builtins.isList l then
      lib.concatMapStringsSep " / " formatLicense l
    else
      l.spdxId or l.shortName or (if builtins.isString l then l else "unknown");

  sourceType =
    pkg:
    let
      names = map (s: s.shortName or "") (lib.toList (pkg.meta.sourceProvenance or [ ]));
    in
    if lib.elem "fromSource" names then
      "source"
    else if lib.elem "binaryNativeCode" names then
      "binary"
    else if lib.elem "binaryBytecode" names then
      "bytecode"
    else
      "source";

  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  metadata =
    name: pkg:
    if (pkg.passthru.hideFromDocs or false) || !(pkg.meta ? mainProgram) then
      null
    else
      {
        inherit name;
        version = pkg.version or "";
        description = pkg.meta.description or "";
        homepage = pkg.meta.homepage or null;
        license = formatLicense (pkg.meta.license or "unknown");
        source = sourceType pkg;
        category = pkg.passthru.category or "Uncategorized";
        mainProgram = pkg.meta.mainProgram;
        platforms = lib.filter (
          s: lib.meta.availableOn (lib.systems.elaborate s) pkg && !(pkg.meta.broken or false)
        ) supportedSystems;
        hasReadme = builtins.pathExists (../. + "/${name}/README.md");
      };

  # Skip `site` itself to avoid infinite recursion.
  packagesJson = builtins.toJSON (
    lib.filter (m: m != null) (lib.mapAttrsToList metadata (removeAttrs allPackages [ "site" ]))
  );
in
stdenvNoCC.mkDerivation {
  name = "llm-agents-site";
  src = ./src;
  nativeBuildInputs = [ jq ];
  passAsFile = [ "packagesJson" ];
  inherit packagesJson;
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r ./* $out/
    jq -c 'sort_by(.name)' "$packagesJsonPath" > $out/packages.json
    touch $out/.nojekyll
    runHook postInstall
  '';
  passthru.hideFromDocs = true;
  meta = {
    description = "Static package search site for llm-agents.nix";
    license = lib.licenses.mit;
    # Some packages throw "Unsupported system" when evaluated on darwin.
    platforms = [ "x86_64-linux" ];
  };
}
