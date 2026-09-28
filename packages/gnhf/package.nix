{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildNpmPackage rec {
  pname = "gnhf";
  version = "0.1.50";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "gnhf";
    tag = "gnhf-v${version}";
    hash = "sha256-SL1qHjbKTOF6a4Aac00Q8vTY8DdWf7dGYcVo7XGWK7w=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-dmQ7bJi4L4ME0imJp9hkkkkITzQksgKdJ2d08SIrMYY=";
  };

  nativeBuildInputs = [ pnpm ];
  npmConfigHook = pnpmConfigHook;

  # npm prune hangs forever in pnpm-managed node_modules
  dontNpmPrune = true;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Ralph/autoresearch-style orchestrator that keeps coding agents running while you sleep";
    homepage = "https://github.com/kunchenguid/gnhf";
    changelog = "https://github.com/kunchenguid/gnhf/releases/tag/gnhf-v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ pikdum ];
    mainProgram = "gnhf";
    platforms = platforms.all;
  };
}
