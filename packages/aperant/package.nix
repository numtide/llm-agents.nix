{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  electron_43,
  python3,
}:

let
  # Upstream pins electron 40, but electron_40 and electron_42 are
  # EOL/insecure in nixpkgs.
  # Electron majors are backwards compatible enough for this app; the build
  # guard below catches the day upstream jumps ahead of what we ship.
  electron = electron_43;
in
buildNpmPackage rec {
  npmDepsFetcherVersion = 2;
  pname = "aperant";
  version = "2.7.6";

  src = fetchFromGitHub {
    owner = "AndyMik90";
    repo = "Aperant";
    tag = "v${version}";
    hash = "sha256-MwT/FGpnAbGjJAGoKJkyL0ngKWtPIpQiCSN2LzHSMAY=";
  };

  npmDepsHash = "sha256-iuN5f2TRD+C1CB/r3DdQEOQMio5x6G0ibNo83mktxrk=";
  makeCacheWritable = true;

  nativeBuildInputs = [ makeWrapper ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  patches = [ ./nix.patch ];

  npmFlags = [ "--ignore-scripts" ];

  buildPhase = ''
    runHook preBuild

    # Fail loudly if upstream moves to an Electron major newer than ours.
    upstream_electron=$(node -p "require('./apps/frontend/package.json').devDependencies.electron")
    upstream_major=''${upstream_electron%%.*}
    nix_major=${lib.versions.major electron.version}
    if (( upstream_major > nix_major )); then
      echo "error: upstream expects electron $upstream_electron (major $upstream_major), but we provide electron ${electron.version} (major $nix_major)"
      echo "Update the electron input in package.nix to match."
      exit 1
    fi

    cd apps/frontend
    npx electron-vite build
    cd ../..

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/aperant

    # Copy electron-vite build output
    cp -r apps/frontend/out $out/share/aperant/
    cp apps/frontend/package.json $out/share/aperant/

    # Copy runtime node_modules from the workspace root (npm hoists deps there).
    # This includes @lydell/node-pty and its platform-specific prebuilt binaries,
    # which are needed at runtime since electron-vite externalizes them.
    npm prune --omit=dev
    # Remove workspace symlinks that point to build-time paths
    find node_modules -maxdepth 1 -type l -delete
    cp -r node_modules $out/share/aperant/

    # Include the Python backend as a resource
    mkdir -p $out/share/aperant/resources/backend
    cp -r apps/backend/* $out/share/aperant/resources/backend/

    mkdir -p $out/bin
    # The app's PythonEnvManager searches for python3 on PATH to create a
    # venv and pip-install backend dependencies at first launch.
    # ELECTRON_FORCE_IS_PACKAGED makes app.isPackaged return true so the
    # app uses production code paths (no DevTools, venv in userData, etc.).
    makeWrapper ${electron}/bin/electron $out/bin/aperant \
      --add-flags "$out/share/aperant" \
      --set ELECTRON_FORCE_IS_PACKAGED 1 \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}

    runHook postInstall
  '';

  doInstallCheck = false;

  passthru.category = "Claude Code Ecosystem";

  meta = {
    description = "Autonomous multi-agent coding framework powered by Claude AI";
    homepage = "https://github.com/AndyMik90/Aperant";
    changelog = "https://github.com/AndyMik90/Aperant/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ xorilog ];
    mainProgram = "aperant";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
