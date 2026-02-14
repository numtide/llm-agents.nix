{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  fetchNpmDepsWithPackuments,
  npmConfigHook,
  makeWrapper,
  electron_39,
  python3,
}:

buildNpmPackage rec {
  pname = "auto-claude";
  version = "2.7.5";

  src = fetchFromGitHub {
    owner = "AndyMik90";
    repo = "Auto-Claude";
    rev = "v${version}";
    hash = "sha256-GBTrrR97AILIESjYt2vkoAE37XkzathOwTiYyaawvMA=";
  };

  npmDeps = fetchNpmDepsWithPackuments {
    inherit src;
    name = "${pname}-${version}-npm-deps";
    hash = "sha256-3Dk50/76SiYfv3YS5JjEvjMOlZ/HcR/rkblZWIx+CNg=";
    fetcherVersion = 2;
  };
  inherit npmConfigHook;
  makeCacheWritable = true;

  nativeBuildInputs = [ makeWrapper ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  postPatch = ''
    # Remove the postinstall script that runs electron-rebuild.
    # @lydell/node-pty ships prebuilt Node-API binaries as platform-specific
    # optional dependencies (e.g. @lydell/node-pty-linux-x64), so rebuilding
    # against Electron headers is not needed.
    substituteInPlace apps/frontend/package.json \
      --replace-fail '"postinstall": "node scripts/postinstall.cjs",' ""
  '';

  npmFlags = [ "--ignore-scripts" ];

  buildPhase = ''
    runHook preBuild

    cd apps/frontend
    npx electron-vite build
    cd ../..

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/auto-claude

    # Copy electron-vite build output
    cp -r apps/frontend/out $out/share/auto-claude/
    cp apps/frontend/package.json $out/share/auto-claude/

    # Copy runtime node_modules from the workspace root (npm hoists deps there).
    # This includes @lydell/node-pty and its platform-specific prebuilt binaries,
    # which are needed at runtime since electron-vite externalizes them.
    npm prune --omit=dev
    # Remove workspace symlinks that point to build-time paths
    find node_modules -maxdepth 1 -type l -delete
    cp -r node_modules $out/share/auto-claude/

    # Include the Python backend as a resource
    mkdir -p $out/share/auto-claude/resources/backend
    cp -r apps/backend/* $out/share/auto-claude/resources/backend/

    mkdir -p $out/bin
    makeWrapper ${electron_39}/bin/electron $out/bin/auto-claude \
      --add-flags "$out/share/auto-claude/out/main/index.js" \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}

    runHook postInstall
  '';

  doInstallCheck = false;

  passthru.category = "Claude Code Ecosystem";

  meta = {
    description = "Autonomous multi-agent coding framework powered by Claude AI";
    homepage = "https://github.com/AndyMik90/Auto-Claude";
    changelog = "https://github.com/AndyMik90/Auto-Claude/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ xorilog ];
    mainProgram = "auto-claude";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
