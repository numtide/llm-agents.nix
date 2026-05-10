{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  makeWrapper,
  versionCheckHook,
}:

let
  pname = "ctxo";
  version = "0.8.1";
  pnpmWorkspaces = [
    "cli"
    "plugin-api"
    "lang-csharp"
    "lang-go"
    "lang-typescript"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "alperhankendi";
    repo = "Ctxo";
    rev = "v${version}";
    hash = "sha256-+h5UylotoYVfTzd7z65yfLhA/1ZQHQ+6LUFP4PoSxoo=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpmWorkspaces;
    pnpm = pnpm_10;
    # pnpmDeps hash observed from a build run
    hash = "sha256-Hbm1ltx7IfINSe9Mo29GarsS1YFVtIuctCNXzobc2iA=";
    fetcherVersion = 2;
  };

  inherit pnpmWorkspaces;

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
  ];

  # Ensure pnpm's deploy can produce prod layout
  buildPhase = ''
    runHook preBuild
    # Build only the workspace packages required by the CLI to avoid building docs/site
    pnpm --filter @ctxo/plugin-api build
    pnpm --filter @ctxo/cli build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Use pnpm deploy to create production layout for the CLI and included workspaces
    pnpm config set inject-workspace-packages true
    pnpm --filter @ctxo/cli --prod --ignore-scripts deploy $out/lib/ctxo
    # Ensure workspace packages are present in the deploy directory
    if [ -d "$out/lib/ctxo/node_modules/@ctxo/plugin-api" ]; then
      true
    else
      if [ -d "packages/plugin-api/dist" ]; then
        mkdir -p $out/lib/ctxo/node_modules/@ctxo/plugin-api
        cp -r packages/plugin-api/dist/* $out/lib/ctxo/node_modules/@ctxo/plugin-api/
      fi
    fi

    # Install wrapper binary
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/ctxo \
      --add-flags $out/lib/ctxo/dist/index.js \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    category = "AI Coding Agents";
  };

  meta = {
    description = "MCP server delivering dependency-aware, history-enriched context for codebases";
    homepage = "https://github.com/alperhankendi/Ctxo";
    changelog = "https://github.com/alperhankendi/Ctxo/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ antono ];
    platforms = lib.platforms.all;
    mainProgram = "ctxo";
  };
})
