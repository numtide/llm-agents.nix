{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  cmake,
  git,
  makeWrapper,
  nodejs,
  pnpm,
  pnpmConfigHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "openclaw";
  version = "2026.2.22";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v${finalAttrs.version}";
    hash = "sha256-xBBEpBRwZlghx2DPCGIpNgTPEMrrBFGkjPVEBrcBGKo=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-IVdoMDuFAPabQMWi7eL2nQZ6hYEb2Tvvf8KRlriHFLo=";
    fetcherVersion = 2;
  };

  nativeBuildInputs = [
    cmake
    git
    makeWrapper
    nodejs
    pnpm
    pnpmConfigHook
  ];

  # Prevent cmake from automatically running in configure phase
  # (it's only needed for npm postinstall scripts)
  dontUseCmakeConfigure = true;

  preBuild = ''
    # rolldown is a transitive dependency (via tsdown), not a direct root
    # dependency. pnpm does not expose its binary in the root node_modules/.bin.
    # bundle-a2ui.sh falls back to 'pnpm dlx rolldown' (requires network) when
    # rolldown is not in PATH, which fails in the Nix sandbox. Create the
    # missing bin link so the pre-fetched rolldown binary is used instead.
    # Use a relative symlink: find returns "node_modules/.pnpm/rolldown@.../bin/cli.mjs"
    # (relative to the build root); strip "node_modules/" and prepend "../" to
    # get the path relative to node_modules/.bin/. An absolute symlink would
    # point into the ephemeral build directory and break after installation.
    rolldown_bin=$(find node_modules/.pnpm -name "cli.mjs" -path "*/rolldown/bin/cli.mjs" | head -1)
    if [ -z "$rolldown_bin" ]; then
      echo "error: rolldown cli.mjs not found in node_modules/.pnpm" >&2
      exit 1
    fi
    ln -sf "../$(echo "$rolldown_bin" | sed 's|^node_modules/||')" node_modules/.bin/rolldown
  '';

  buildPhase = ''
    runHook preBuild

    pnpm build

    # Build the UI
    pnpm ui:build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib/openclaw}

    cp -r * $out/lib/openclaw/

    # Remove development/build files not needed at runtime
    pushd $out/lib/openclaw
    rm -rf \
      src \
      test \
      apps \
      Swabble \
      Peekaboo \
      tsconfig.json \
      vitest.config.ts \
      vitest.e2e.config.ts \
      vitest.live.config.ts \
      Dockerfile \
      Dockerfile.sandbox \
      Dockerfile.sandbox-browser \
      docker-compose.yml \
      docker-setup.sh \
      README-header.png \
      CHANGELOG.md \
      CONTRIBUTING.md \
      SECURITY.md \
      appcast.xml \
      pnpm-lock.yaml \
      pnpm-workspace.yaml \
      assets/dmg-background.png \
      assets/dmg-background-small.png

    # Remove test files scattered throughout
    find . -name "__screenshots__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.test.ts" -delete
    popd

    makeWrapper ${nodejs}/bin/node $out/bin/openclaw \
      --add-flags "$out/lib/openclaw/dist/entry.js"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Your own personal AI assistant. Any OS. Any Platform. The lobster way";
    homepage = "https://openclaw.ai";
    changelog = "https://github.com/openclaw/openclaw/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
    mainProgram = "openclaw";
  };
})
