{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  fd,
  makeWrapper,
  node-gyp,
  nodejs,
  python3,
  pnpm_10,
  pnpmConfigHook,
  ripgrep,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pnpm = pnpm_10.override { nodejs-slim = nodejs; };

  pnpmWorkspaces = [
    "."
    "@moonshot-ai/acp-adapter"
    "@moonshot-ai/agent-core"
    "@moonshot-ai/server"
    "@moonshot-ai/kaos"
    "@moonshot-ai/kosong"
    "@moonshot-ai/migration-legacy"
    "@moonshot-ai/kimi-code-sdk"
    "@moonshot-ai/kimi-code-oauth"
    "@moonshot-ai/pi-tui"
    "@moonshot-ai/protocol"
    "@moonshot-ai/kimi-telemetry"
    "@moonshot-ai/kimi-code"
    "@moonshot-ai/kimi-web"
    "@moonshot-ai/vis-server"
    "@moonshot-ai/vis-web"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "kimi-code";
  version = "0.24.1";

  src = fetchFromGitHub {
    owner = "MoonshotAI";
    repo = "kimi-code";
    tag = "@moonshot-ai/kimi-code@${finalAttrs.version}";
    hash = "sha256-Z+lSklmYrdf+6oaUXXKZn6tdPNhxTNizUreDwOumWgo=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm pnpmWorkspaces;
    fetcherVersion = 3;
    hash = "sha256-1mZo6wZydwYTVsNlxkI4fbu4KLvZQzBSj3hTmvkFNT4=";
  };

  inherit pnpmWorkspaces;

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm
    (pnpmConfigHook.override { inherit pnpm; })
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    # to compile node-pty (see installPhase)
    node-gyp
    python3
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

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      # node-pty ships prebuilds only for darwin/win32 and the deploy above
      # skips install scripts, so compile the Linux addon here.
      pushd $out/lib/kimi-code/node_modules/.pnpm/node-pty@*/node_modules/node-pty
      node-gyp rebuild --nodedir=${nodejs}
      # keep only the compiled addon
      find build -mindepth 1 -maxdepth 1 ! -name Release -exec rm -rf {} +
      find build/Release -mindepth 1 ! -name '*.node' -exec rm -rf {} +
      popd
    ''}

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
    maintainers = with flake.lib.maintainers; [ mnixry ];
    mainProgram = "kimi";
    platforms = lib.platforms.unix;
  };
})
