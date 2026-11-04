{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  fd,
  makeWrapper,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  ripgrep,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pnpm = pnpm_10.override { nodejs-slim = nodejs; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "kimi-code";
  version = "2.4.1";

  src = fetchFromGitHub {
    owner = "MoonshotAI";
    repo = "kimi-code";
    tag = "@moonshot-ai/kimi-code@${finalAttrs.version}";
    hash = "sha256-UkA/UG9qY9L/kTM+oDPsgQ/EzTwtFt9yDBXsz530xOI=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-fvtkW8HSacFek+jT0t7v3WcYsSTfI22+4kDEyEYHFlY=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm
    (pnpmConfigHook.override { inherit pnpm; })
  ];

  buildPhase = ''
    runHook preBuild

    pnpm --filter @moonshot-ai/kimi-code build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    pnpm config set inject-workspace-packages true
    pnpm --filter @moonshot-ai/kimi-code --prod --ignore-scripts deploy $out/lib/kimi-code

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/kimi \
      --add-flags $out/lib/kimi-code/dist/main.mjs \
      --set KIMI_CODE_NO_AUTO_UPDATE 1 \
      --prefix PATH : ${
        lib.makeBinPath [
          fd
          ripgrep
        ]
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru = {
    category = "AI Coding Agents";
    tests.smoke =
      runCommand "kimi-code-smoke-test" { nativeBuildInputs = [ finalAttrs.finalPackage ]; }
        ''
          export HOME=$(mktemp -d)
          grep -F ${lib.getBin fd}/bin ${finalAttrs.finalPackage}/bin/kimi
          grep -F ${lib.getBin ripgrep}/bin ${finalAttrs.finalPackage}/bin/kimi
          kimi --version | grep -Fx ${lib.escapeShellArg finalAttrs.version}
          kimi provider list | grep -Fx "No providers configured."
          touch $out
        '';
  };

  meta = {
    description = "The Starting Point for Next-Gen Agents";
    homepage = "https://github.com/MoonshotAI/kimi-code";
    changelog = "https://github.com/MoonshotAI/kimi-code/releases/tag/%40moonshot-ai%2Fkimi-code%40${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ mnixry ];
    mainProgram = "kimi";
    platforms = lib.platforms.unix;
  };
})
