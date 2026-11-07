{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  versionCheckHook,
}:

buildNpmPackage rec {
  pname = "nanocoder";
  version = "1.32.0";

  src = fetchFromGitHub {
    owner = "Nano-Collective";
    repo = "nanocoder";
    tag = "v${version}";
    hash = "sha256-cq+GC+obqPcvKewMY4ZeMQT1Ir51Wlmk281yxLUd/fE=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-vKLdWxKe++cLZAG+TrMBxM0WM0KkIhUl+kLq4G/Xx4o=";
  };

  nativeBuildInputs = [ pnpm_11 ];
  npmConfigHook = pnpmConfigHook;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  dontNpmPrune = true; # hangs forever on both Linux/darwin

  # pnpm links the plugins/vscode workspace package into node_modules, but
  # npm pack does not ship plugins/, leaving a dangling symlink in $out.
  preFixup = ''
    rm -f $out/lib/node_modules/@nanocollective/nanocoder/node_modules/.pnpm/node_modules/nanocoder-vscode
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "A beautiful local-first coding agent running in your terminal - built by the community for the community ⚒";
    homepage = "https://github.com/Nano-Collective/nanocoder";
    changelog = "https://github.com/Nano-Collective/nanocoder/releases";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "nanocoder";
  };
}
