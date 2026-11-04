{
  formatelf,
  bun,
  copyDesktopItems,
  electron_43,
  fetchFromGitHub,
  flake,
  lib,
  makeBinaryWrapper,
  makeDesktopItem,
  mkUpdater,
  models-dev,
  nodejs,
  stdenv,
  stdenvNoCC,
  writableTmpDirAsHomeHook,
}:

let
  electron = electron_43;
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash nodeModulesHash;
  nodePlatform = "${stdenvNoCC.hostPlatform.node.platform}-${stdenvNoCC.hostPlatform.node.arch}";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opencode-desktop";
  inherit version;

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${finalAttrs.version}";
    inherit hash;
  };

  node_modules = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --cpu="*" \
        --frozen-lockfile \
        --filter ./ \
        --filter ./packages/app \
        --filter ./packages/desktop \
        --filter ./packages/opencode \
        --filter ./packages/shared \
        --ignore-scripts \
        --no-progress \
        --os="*"

      bun --bun ./nix/scripts/canonicalize-node-modules.ts
      bun --bun ./nix/scripts/normalize-bun-binaries.ts

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      find . -type d -name node_modules -exec cp -R --parents {} $out \;

      # Windows executables fetched via --os="*" are never used on the
      # platforms we build for; drop them from the fixed output.
      find $out -type f -name '*.exe' -delete

      runHook postInstall
    '';

    dontFixup = true;

    outputHash = nodeModulesHash;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    bun
    nodejs # for patchShebangs node_modules
    makeBinaryWrapper
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
    formatelf
    copyDesktopItems
  ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    (lib.getLib stdenv.cc.cc)
  ];

  strictDeps = true;

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    NODE_OPTIONS = "--max-old-space-size=4096";
    OPENCODE_CHANNEL = "prod";
    MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
    OPENCODE_DISABLE_MODELS_FETCH = true;
  }
  // lib.optionalAttrs stdenvNoCC.hostPlatform.isDarwin {
    CSC_IDENTITY_AUTO_DISCOVERY = "false";
  };

  postPatch = ''
    # The auto-updater would try to download and run an upstream binary that
    # isn't patched for Nix. Disable it at source.
    substituteInPlace packages/desktop/src/main/constants.ts \
      --replace-fail 'app.isPackaged && CHANNEL !== "dev"' 'false'

    # Relax Bun version check to be a warning instead of an error
    substituteInPlace packages/script/src/index.ts \
      --replace-fail 'throw new Error(`This script requires bun@''${expectedBunVersionRange}' \
                     'console.warn(`Warning: This script requires bun@''${expectedBunVersionRange}'
  '';

  configurePhase = ''
    runHook preConfigure

    cp -R ${finalAttrs.node_modules}/. .
    chmod -R u+w node_modules packages/*/node_modules

    # node_modules is fetched with --os/--cpu="*" so the FOD hash is platform
    # independent; drop foreign native prebuilds here so electron-builder
    # doesn't copy them into app.asar.
    shopt -s nullglob
    for p in node_modules/.bun/* {.,packages/*}/node_modules/{,@*/}*; do
      name=''${p##*node_modules/}
      case "''${name#.bun/}" in
        *musl*) rm -rf "$p" ;;
        *${nodePlatform}*) ;;
        *darwin*|*linux*|*win32*|*android*|*freebsd*|*aix*) rm -rf "$p" ;;
      esac
    done
    shopt -u nullglob
    find node_modules packages/*/node_modules -xtype l -delete

    patchShebangs node_modules
    patchShebangs packages/*/node_modules

    runHook postConfigure
  '';

  preBuild = lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    # Patch electron-builder to skip code signing on macOS.
    for f in $(find node_modules -path "*/app-builder-lib/out/codeSign/macCodeSign.js" -type f 2>/dev/null); do
      substituteInPlace "$f" \
        --replace-fail "async function getValidIdentities" \
        "async function getValidIdentities() { return []; }; async function getValidIdentities_DISABLED"
    done
  '';

  buildPhase = ''
    runHook preBuild

    # Build the opencode node bundle (needed by the desktop sidecar)
    cd packages/opencode
    bun --bun ./script/build-node.ts --skip-install
    cd ../..

    # Prepare desktop app
    cd packages/desktop

    # Copy prod icons
    cp -R icons/prod resources/icons

    # Build with electron-vite
    node_modules/.bin/electron-vite build

    # Package with electron-builder (unpacked directory mode)
    cp -r "${electron.dist}" $HOME/.electron-dist
    chmod -R u+w $HOME/.electron-dist

    node_modules/.bin/electron-builder --dir \
      --config=electron-builder.config.ts \
      --config.electronDist="$HOME/.electron-dist" \
      --config.electronVersion=${electron.version} \
      --config.asarUnpack='**/*.node' \
      ${lib.optionalString stdenvNoCC.hostPlatform.isDarwin "--config.mac.identity=null"}

    cd ../..

    runHook postBuild
  '';

  desktopItems = lib.optional stdenvNoCC.hostPlatform.isLinux (makeDesktopItem {
    name = "ai.opencode.desktop";
    desktopName = "OpenCode";
    exec = "opencode-desktop %U";
    icon = "opencode-desktop";
    startupWMClass = "ai.opencode.desktop";
    categories = [ "Development" ];
    mimeTypes = [ "x-scheme-handler/opencode" ];
  });

  installPhase =
    let
      appDir = if stdenvNoCC.hostPlatform.isAarch64 then "linux-arm64-unpacked" else "linux-unpacked";
    in
    lib.concatLines [
      ''
        runHook preInstall
      ''
      (lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
        mkdir -p $out/Applications $out/bin
        mv packages/desktop/dist/mac-*/OpenCode.app "$out/Applications/OpenCode.app"
        ln -s "$out/Applications/OpenCode.app/Contents/MacOS/OpenCode" $out/bin/opencode-desktop
      '')
      (lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        mkdir -p $out/opt/opencode-desktop
        appDir="packages/desktop/dist/${appDir}"
        [ -d "$appDir" ] || { echo "no electron-builder output dir found: $appDir"; exit 1; }
        cp -r "$appDir/resources" $out/opt/opencode-desktop/

        for size in 32 64 128; do
          install -Dm644 \
            packages/desktop/resources/icons/''${size}x''${size}.png \
            $out/share/icons/hicolor/''${size}x''${size}/apps/opencode-desktop.png
        done
        install -Dm644 packages/desktop/resources/icons/128x128@2x.png \
          $out/share/icons/hicolor/256x256/apps/opencode-desktop.png

        makeWrapper ${lib.getExe electron} $out/bin/opencode-desktop \
          --inherit-argv0 \
          --set ELECTRON_FORCE_IS_PACKAGED 1 \
          --add-flags $out/opt/opencode-desktop/resources/app.asar
      '')
      ''
        runHook postInstall
      ''
    ];

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "github-source";
    purl = "pkg:github/anomalyco/opencode";
    depHashKey = "nodeModulesHash";
  };

  meta = {
    description = "AI coding agent desktop client";
    homepage = "https://opencode.ai";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ adithyagenie ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "opencode-desktop";
  };
})
