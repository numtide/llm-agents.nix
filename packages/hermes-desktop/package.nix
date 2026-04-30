{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dbus-glib,
  expat,
  glib,
  gsettings-desktop-schemas,
  hicolor-icon-theme,
  gtk2,
  gtk3,
  libgbm,
  libglvnd,
  libdbusmenu,
  libdbusmenu-gtk2,
  libX11,
  libxcb,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libxkbcommon,
  libXrandr,
  nspr,
  nss,
  pango,
  udev,
}:

let
  pname = "hermes-desktop";
  version = "0.3.0";

  src = fetchurl {
    url = "https://github.com/fathah/hermes-desktop/releases/download/v${version}/hermes-desktop-${version}.AppImage";
    hash = "sha256-/yw0evwz+lJE/Avavuvp2vKS2FrFiEDsClEsTcy5C2k=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    dbus-glib
    expat
    glib
    gsettings-desktop-schemas
    hicolor-icon-theme
    gtk2
    gtk3
    libgbm
    libglvnd
    libdbusmenu
    libdbusmenu-gtk2
    libX11
    libxcb
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libxkbcommon
    libXrandr
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    udev
  ];

  runtimeDependencies = [
    libgbm
    libglvnd
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/hermes-desktop $out/bin $out/share/applications $out/share/icons/hicolor/512x512/apps
    cp -R ${appimageContents}/. $out/lib/hermes-desktop/
    chmod -R u+w $out/lib/hermes-desktop

    makeWrapper $out/lib/hermes-desktop/hermes-desktop $out/bin/hermes-desktop \
      --chdir $out/lib/hermes-desktop \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libgbm
          libglvnd
        ]
      } \
      --set GSETTINGS_SCHEMA_DIR ${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}/glib-2.0/schemas \
      --prefix XDG_DATA_DIRS : ${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${gtk3}/share/gsettings-schemas/${gtk3.name}:${hicolor-icon-theme}/share:$out/share \
      --add-flags --no-sandbox \
      --add-flags --disable-gpu-sandbox

    install -Dm644 $out/lib/hermes-desktop/hermes-desktop.png \
      $out/share/icons/hicolor/512x512/apps/hermes-desktop.png
    install -Dm644 $out/lib/hermes-desktop/hermes-desktop.desktop \
      $out/share/applications/hermes-desktop.desktop
    substituteInPlace $out/share/applications/hermes-desktop.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=hermes-desktop' \
      --replace-fail 'Icon=hermes-desktop' 'Icon=hermes-desktop'

    runHook postInstall
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Desktop companion for Hermes Agent";
    homepage = "https://github.com/fathah/hermes-desktop";
    changelog = "https://github.com/fathah/hermes-desktop/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "hermes-desktop";
  };
}
