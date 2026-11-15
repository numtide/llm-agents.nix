{
  lib,
  flake,
  buildGo127Module,
  fetchFromGitHub,
  fetchNpmDeps,
  nodejs,
  npmHooks,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData)
    version
    hash
    vendorHash
    npmDepsHash
    ;
in
buildGo127Module (finalAttrs: {
  pname = "gomodel";
  inherit version;

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "ENTERPILOT";
    repo = "GoModel";
    tag = "v${finalAttrs.version}";
    inherit hash;
  };

  inherit vendorHash;

  # The web dashboard is a separate Svelte/TypeScript workspace that the Go
  # binary embeds. Its dependencies have to be vendored before the Go build so
  # the embedded assets are present in the module cache.
  npmDeps = fetchNpmDeps {
    src = "${finalAttrs.src}/web/dashboard";
    hash = npmDepsHash;
  };

  # paraglide-js plugins are resolved via `./node_modules/...` paths in
  # `project.inlang/settings.json`, so no patchPhase is needed.

  npmRoot = "web/dashboard";
  nativeBuildInputs = [
    nodejs
    npmHooks.npmConfigHook
  ];

  overrideModAttrs = oldAttrs: {
    # Do not add `npmConfigHook` to `goModules`
    nativeBuildInputs = lib.remove npmHooks.npmConfigHook oldAttrs.nativeBuildInputs;
    # Do not run `preBuild` when building `goModules`
    preBuild = null;
  };

  # Tests require network services (Redis, Postgres, etc.)
  doCheck = false;

  preBuild = ''
    npm --prefix="$npmRoot" run build
  '';

  ldflags = [
    "-s"
    "-w"
    "-X github.com/enterpilot/gomodel/internal/version.Version=${finalAttrs.version}"
    "-X github.com/enterpilot/gomodel/internal/version.Commit=v${finalAttrs.version}"
    "-X github.com/enterpilot/gomodel/internal/version.Date=1970-01-01T00:00:00Z"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Utilities";

  meta = {
    description = "Fast and resource-efficient AI gateway with caching, cost tracking, budgets, rate limits, virtual models, failover, MCP gateway, plugins and workflows";
    homepage = "https://github.com/ENTERPILOT/GoModel";
    changelog = "https://github.com/ENTERPILOT/GoModel/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ ser ];
    mainProgram = "gomodel";
    platforms = lib.platforms.all;
  };
})
