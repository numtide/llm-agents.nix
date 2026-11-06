{
  lib,
  flake,
  stdenv,
  fetchPnpmDeps,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  electron_44,
  multica,
}:

let
  electron = electron_44;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "multica-desktop";
  inherit (multica) version src;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    hash = "sha256-b7Cs2ZN5t/CTdrgVkNQqv0A2tr3ASWoHBeMSHc9FVEA=";
    fetcherVersion = 3;
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
    copyDesktopItems
  ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  # Bundle main-process deps so no node_modules is needed at runtime.
  postPatch = ''
    substituteInPlace apps/desktop/electron.vite.config.ts \
      --replace-fail "plugins: [externalizeDepsPlugin()]," "build: { externalizeDeps: false },"
  '';

  buildPhase = ''
    runHook preBuild
    pnpm --filter @multica/desktop exec electron-vite build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/share/multica-desktop
    mkdir -p $app/resources/bin
    cp -r apps/desktop/out $app/
    cp -r apps/desktop/resources/. $app/resources/
    ln -s ${lib.getExe multica} $app/resources/bin/multica
    # app.getAppPath() is out/main when started on the bundle directly.
    ln -s ../../resources $app/out/main/resources

    install -Dm644 apps/desktop/build/icon.png \
      $out/share/icons/hicolor/512x512/apps/multica.png

    makeWrapper ${lib.getExe electron} $out/bin/multica-desktop \
      --add-flags $app/out/main/index.js \
      --inherit-argv0

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "multica-desktop";
      desktopName = "Multica";
      exec = "multica-desktop %U";
      icon = "multica";
      categories = [ "Utility" ];
      startupWMClass = "Multica";
      mimeTypes = [ "x-scheme-handler/multica" ];
    })
  ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Desktop client for the Multica platform";
    homepage = "https://github.com/multica-ai/multica";
    changelog = "https://github.com/multica-ai/multica/releases/tag/v${finalAttrs.version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = lib.platforms.linux;
    mainProgram = "multica-desktop";
  };
})
