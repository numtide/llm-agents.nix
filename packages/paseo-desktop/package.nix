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
  pname = "paseo-desktop";
  version = "0.1.64";

  src = fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-${version}-x86_64.AppImage";
    hash = "sha256-rWGmq4oYR4jPqdjMo20LFA/9pnPIF34JCuQr67SJW4k=";
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

  autoPatchelfIgnoreMissingDeps = [
    "libvips-cpp.so.8.17.3"
  ];

  runtimeDependencies = [
    libgbm
    libglvnd
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/paseo-desktop $out/bin $out/share/applications
    cp -R ${appimageContents}/. $out/lib/paseo-desktop/
    chmod -R u+w $out/lib/paseo-desktop

    rm -rf \
      $out/lib/paseo-desktop/resources/app.asar.unpacked/node_modules/koffi/build/koffi/freebsd_* \
      $out/lib/paseo-desktop/resources/app.asar.unpacked/node_modules/koffi/build/koffi/musl_* \
      $out/lib/paseo-desktop/resources/app.asar.unpacked/node_modules/koffi/build/koffi/openbsd_* \
      $out/lib/paseo-desktop/resources/app.asar.unpacked/node_modules/@mariozechner/clipboard-linux-x64-musl

    makeWrapper $out/lib/paseo-desktop/Paseo $out/bin/paseo-desktop \
      --chdir $out/lib/paseo-desktop \
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

    cp -R $out/lib/paseo-desktop/usr/share/icons $out/share/
    install -Dm644 $out/lib/paseo-desktop/Paseo.desktop \
      $out/share/applications/paseo-desktop.desktop
    substituteInPlace $out/share/applications/paseo-desktop.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=paseo-desktop %U' \
      --replace-fail 'Icon=Paseo' 'Icon=Paseo'

    runHook postInstall
  '';

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Voice-controlled desktop development environment for AI coding agents";
    homepage = "https://paseo.sh";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${version}";
    license = licenses.agpl3Plus;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "paseo-desktop";
  };
}
