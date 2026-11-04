{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildNpmPackage rec {
  pname = "gnhf";
  version = "0.1.52";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "gnhf";
    tag = "gnhf-v${version}";
    hash = "sha256-p1yqolCvowFRBfxAOON6PQCflQlpHTeMajwjDIMC7i4=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-CBjHhN5VxVDl6xOn2fDowPhh22MueNwb5jZ/rmKQ0Tw=";
  };

  nativeBuildInputs = [ pnpm_11 ];
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
