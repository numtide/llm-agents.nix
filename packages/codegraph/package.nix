{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  flake,
  versionCheckHook,
}:

buildNpmPackage rec {
  npmDepsFetcherVersion = 2;
  pname = "codegraph";
  version = "1.6.4";

  src = fetchFromGitHub {
    owner = "colbymchenry";
    repo = "codegraph";
    tag = "v${version}";
    hash = "sha256-V0Q/tivtO64vYkFOeWFXu1gGZCIAAtiT1Htz5xNkFns=";
  };

  npmDepsHash = "sha256-RzsL5Z5/ozfJe51l/zNbUjfypwM5aOPm7w10refZ6OU=";
  makeCacheWritable = true;

  # The ui workspace is only needed at build time (emitted to dist/viewer) and
  # is not installed, which leaves its node_modules link dangling.
  postInstall = ''
    rm $out/lib/node_modules/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-ui
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.category = "Memory & Code Intelligence";

  meta = {
    description = "Semantic code intelligence for AI coding agents";
    homepage = "https://github.com/colbymchenry/codegraph";
    changelog = "https://github.com/colbymchenry/codegraph/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ Bad3r ];
    mainProgram = "codegraph";
    platforms = lib.platforms.all;
  };
}
