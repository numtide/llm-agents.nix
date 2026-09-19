{
  lib,
  stdenvNoCC,
  jq,
  allPackages,
}:

let
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
  # The document root lives at share/llm-agents-site so that the package root
  # stays FHS-like; lib/hercules-ci.nix copies that directory to gh-pages.
  installPhase = ''
    runHook preInstall
    doc=$out/share/llm-agents-site
    mkdir -p "$doc"
    cp -r ./* "$doc"/
    # GitHub Pages caches assets for 10 minutes. Mismatched index.html and
    # app.js after a deploy broke the page, so pin assets to this build.
    v=$(basename $out | cut -c1-12)
    sed -i -e "s|app.js|app.js?v=$v|" -e "s|style.css|style.css?v=$v|" "$doc"/index.html
    jq -c 'sort_by(.name)' "$packagesJsonPath" > "$doc"/packages.json
    touch "$doc"/.nojekyll
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
