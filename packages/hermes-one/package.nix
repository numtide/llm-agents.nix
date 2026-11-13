{
  lib,
  flake,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  electron_43,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  python3,
  node-gyp,
}:

let
  # Upstream pins ^44, newest in nixpkgs.
  electron = electron_43;
in
buildNpmPackage rec {
  pname = "hermes-one";
  version = "0.7.8";

  src = fetchFromGitHub {
    owner = "fathah";
    repo = "hermes-desktop";
    tag = "v${version}";
    hash = "sha256-tjzxSWFRNEsJ0EJS0zXFIdR4Z4q6HlaZRl9l10l2FBo=";
  };

  npmDepsHash = "sha256-6XseMdCQBDyfbG3cbDXOjCMWWH5Ec6pJnj/leFFpseM=";
  npmDepsFetcherVersion = 2;

  # Upstream postinstall runs electron-builder install-app-deps and husky;
  # neither works in the sandbox. Native modules are rebuilt explicitly below.
  npmFlags = [ "--ignore-scripts" ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  nativeBuildInputs = [
    makeWrapper
    python3
    node-gyp
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ];

  buildPhase = ''
    runHook preBuild

    npx electron-vite build

    # Prune first, it reinstalls better-sqlite3 and would drop the addon.
    npm prune --omit=dev
    # N-API addon, but the shipped prebuilds are not usable on NixOS.
    rm -r node_modules/better-sqlite3/prebuilds
    (cd node_modules/better-sqlite3 && node-gyp rebuild --release --nodedir=${electron.headers})

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/hermes-one $out/bin

    cp -r out package.json $out/share/hermes-one/

    # Runtime dependencies for the main process: electron-vite externalizes
    # everything in package.json "dependencies" (better-sqlite3, i18next,
    # electron-updater, ...), so they must exist in node_modules.
    mv node_modules/better-sqlite3/build/Release/better_sqlite3.node .
    rm -r node_modules/better-sqlite3/build
    install -D better_sqlite3.node node_modules/better-sqlite3/build/Release/better_sqlite3.node
    cp -r node_modules $out/share/hermes-one/

    install -Dm644 build/icon.png $out/share/icons/hicolor/512x512/apps/hermes-one.png

    # app.isPackaged stays false on purpose: upstream skips its
    # electron-updater code path in that case, which is what we want for a
    # store-managed install.
    makeWrapper ${lib.getExe electron} $out/bin/hermes-one \
      --add-flags $out/share/hermes-one \
      --inherit-argv0

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "hermes-one";
      desktopName = "Hermes One";
      comment = "Self-improving AI assistant desktop app";
      exec = "hermes-one %U";
      icon = "hermes-one";
      categories = [ "Utility" ];
      # Electron derives the window class from upstream's package.json name.
      startupWMClass = "hermes-desktop";
    })
  ];

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Hermes One, community desktop companion for Hermes Agent";
    homepage = "https://github.com/fathah/hermes-desktop";
    changelog = "https://github.com/fathah/hermes-desktop/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "hermes-one";
  };
}
