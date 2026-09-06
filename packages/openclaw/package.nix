{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  cmake,
  git,
  makeWrapper,
  nodejs,
  # Lockfile predates pnpm 11's stricter overrides/patchedDependencies
  # validation; pin pnpm 10 until upstream regenerates the lockfile.
  pnpm_10,
  pnpmConfigHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pnpm = pnpm_10;
  # pnpm 10.33+ rejects patchedDependencies mismatch between lockfile
  # and pnpm-workspace.yaml; strip from both for frozen install.
  stripPatchedDeps = ''
    sed -i '/^patchedDependencies:/,/^[^ ]/{/^patchedDependencies:/d;/^  /d;}' pnpm-lock.yaml pnpm-workspace.yaml
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "openclaw";
  version = "2026.9.2";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    tag = "v${finalAttrs.version}";
    hash = "sha256-VRY5aJDmctoblL9hPb//Y3H1+1zWoKa0sbApdHu4saY=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    hash = "sha256-NUEfkKFibAY3jgM5/e7HtV23nM5UB9iKhy/w8xIIQ+0=";
    fetcherVersion = 3;
    prePnpmInstall = stripPatchedDeps;
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

  # The build OOM-kills on memory-constrained aarch64 builders: rolldown (the
  # Rust bundler behind tsdown) spawns one rayon worker per core, and the
  # node-side ui:build/tsc lets V8 grow its heap toward the host total. Bound
  # both so peak RSS stays within the builder's limit.
  env = {
    NODE_OPTIONS = "--max-old-space-size=4096";
    # the sandbox hides the cgroup limit tsdown-build wants to derive this from
    OPENCLAW_TSDOWN_MAX_OLD_SPACE_MB = "4096";
    # fs-safe's native openat2 path returns ENOSYS on some builders
    FS_SAFE_NATIVE_MODE = "off";
    RAYON_NUM_THREADS = "4";
  };

  postPatch = stripPatchedDeps;

  preBuild = ''
    # rolldown is a transitive dependency (via tsdown), not a direct root
    # dependency, so pnpm does not link its binary into node_modules/.bin.
    # scripts/bundle-a2ui.mjs probes two hard-coded paths under
    # node_modules/.pnpm/ (the layout produced by pnpm's default isolated
    # node-linker) and falls back to 'pnpm dlx rolldown' (network) when neither
    # exists. Upstream however sets `node-linker=hoisted` in .npmrc, so the
    # package ends up at node_modules/rolldown instead and the probes miss it.
    # Link it where the script expects so the pre-fetched binary is used.
    if [ ! -e node_modules/rolldown/bin/cli.mjs ]; then
      echo "error: rolldown cli.mjs not found in node_modules" >&2
      exit 1
    fi
    mkdir -p node_modules/.pnpm/node_modules
    ln -sfT ../../rolldown node_modules/.pnpm/node_modules/rolldown
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
  # Upstream tags may carry a "-N" rebuild suffix (e.g. v2026.5.7) while
  # `openclaw --version` only reports the base version. Strip the suffix
  # before versionCheckHook compares it against the command output.
  preVersionCheck = ''
    version=${lib.head (lib.splitString "-" finalAttrs.version)}
  '';

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
