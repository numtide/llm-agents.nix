{
  lib,
  buildGoModule,
  fetchFromGitHub,
  stdenv,
  pkg-config,
  gtk3,
  webkitgtk_4_1,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  imagemagick,
  ast-grep,
  gotools,
  bun,
  xdg-utils,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule (finalAttrs: {
  pname = "magpie";
  version = "0.1.3226";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    tag = "v${finalAttrs.version}";
    hash = "sha256-psFZ2Mij/6XVTVhjEOcPHQTzwll+f/ZRI/nMkLCFHwQ=";
  };

  vendorHash = "sha256-tYSKQMQa3cdhED4Yss/Frxd5midK6o2WND7/fRUtSuc=";

  # Apply the runtime policies before compiling the installed application.
  postPatch = ''
    bash ${./patch.sh} ${stdenv.hostPlatform.parsed.kernel.name} \
      "$out/bin/magpie" ${lib.getExe bun}
  '';

  subPackages = [ "." ];

  tags = [ "production" ] ++ lib.optional stdenv.hostPlatform.isLinux "gtk3";

  env.CGO_ENABLED = "1";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${finalAttrs.version}"
  ];

  # The suite drives a live desktop, downloads Bun plugins and needs
  # per-version source adaptations; upstream reshapes it too often to keep
  # green here.
  doCheck = false;

  nativeBuildInputs = [
    ast-grep
    gotools
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    pkg-config
    wrapGAppsHook3
    copyDesktopItems
    imagemagick
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gtk3
    webkitgtk_4_1
  ];

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
      --set MAGPIE_BUN ${lib.getExe bun}
    )
  '';

  desktopItems = lib.optionals stdenv.hostPlatform.isLinux [
    (makeDesktopItem {
      name = "magpie";
      desktopName = "magpie";
      comment = "Every agent's model. One place.";
      exec = "magpie %u";
      icon = "magpie";
      startupWMClass = "magpie";
      terminal = false;
      categories = [
        "Development"
        "Utility"
      ];
      mimeTypes = [ "x-scheme-handler/magpie" ];
    })
  ];

  postInstall =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      install -Dm644 internal/gui/icon-1024.png \
        $out/share/icons/hicolor/512x512@2/apps/magpie.png
      mkdir -p $out/share/icons/hicolor/512x512/apps
      magick internal/gui/icon-1024.png -resize 512x512 \
        $out/share/icons/hicolor/512x512/apps/magpie.png
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      app="$out/Applications/magpie.app"
      mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
      mv "$out/bin/magpie" "$app/Contents/MacOS/magpie"
      ln -s "$app/Contents/MacOS/magpie" "$out/bin/magpie"
      cp build/darwin/magpie.icns build/darwin/Assets.car "$app/Contents/Resources/"
      substitute build/darwin/Info.plist "$app/Contents/Info.plist" \
        --replace-fail '@VERSION@' '${finalAttrs.version}'
    '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "Utilities";

  meta = {
    description = "Manage models, providers, and accounts for AI coding agents in one place";
    homepage = "https://github.com/yetone/magpie";
    changelog = "https://github.com/yetone/magpie/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ xyenon ];
    mainProgram = "magpie";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
