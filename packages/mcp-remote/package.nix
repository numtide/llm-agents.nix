{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_10,
  pnpmConfigHook,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  pname = "mcp-remote";
  version = "0.16.6";

  src = fetchFromGitHub {
    owner = "punkpeye";
    repo = "mcp-remote";
    tag = "v${finalAttrs.version}";
    hash = "sha256-DQGo8IegqRFNNhyOC3isRc1WHH9GIoFiKvKfpF27H98=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-/Gjd1zDlV134k5wLqVkfiwyjrk0bbOXWDyvN5NUBOPc=";
  };

  nativeBuildInputs = [ pnpm_10 ];
  npmConfigHook = pnpmConfigHook;

  preBuild = ''
    # semantic-release updates the manifest only when publishing to npm.
    npm pkg set version=${finalAttrs.version}
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm test
    runHook postCheck
  '';

  # Prune with pnpm; npm pack must not rebuild after removing dev dependencies.
  dontNpmPrune = true;
  npmPackFlags = [ "--ignore-scripts" ];
  preInstall = ''
    pnpm prune --prod --ignore-scripts
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Utilities";

  meta = {
    description = "Connect MCP clients that only support local (stdio) servers to a remote MCP server";
    homepage = "https://github.com/punkpeye/mcp-remote";
    changelog = "https://github.com/punkpeye/mcp-remote/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ mnixry ];
    mainProgram = "mcp-remote";
    platforms = lib.platforms.unix;
  };
})
