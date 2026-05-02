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
  pname = "vessel-browser";
  version = "0.1.78";

  src = fetchurl {
    url = "https://github.com/unmodeled-tyler/vessel-browser/releases/download/v${version}/Vessel-${version}-x86_64.AppImage";
    hash = "sha256-8NpQ+mxeZp+UnAxLSi8SNPB7VcHZ8IEjeweWt4pAxL0=";
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

    mkdir -p $out/lib/vessel-browser $out/bin $out/share/applications $out/share/icons/hicolor/512x512/apps
    cp -R ${appimageContents}/. $out/lib/vessel-browser/
    chmod -R u+w $out/lib/vessel-browser

    makeWrapper $out/lib/vessel-browser/vessel $out/bin/vessel-browser \
      --chdir $out/lib/vessel-browser \
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

    install -Dm644 $out/lib/vessel-browser/vessel.png \
      $out/share/icons/hicolor/512x512/apps/vessel-browser.png
    install -Dm644 $out/lib/vessel-browser/vessel.desktop \
      $out/share/applications/vessel-browser.desktop
    substituteInPlace $out/share/applications/vessel-browser.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=vessel-browser' \
      --replace-fail 'Icon=vessel' 'Icon=vessel-browser'

    runHook postInstall
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Agent-oriented browser with durable state and MCP control";
    homepage = "https://github.com/unmodeled-tyler/vessel-browser";
    changelog = "https://github.com/unmodeled-tyler/vessel-browser/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "vessel-browser";
  };
}
