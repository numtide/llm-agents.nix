{
  lib,
  flake,
  platformSource,
  mkUpdater,
  stdenvNoCC,
  bintools,
  formatelf,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  coreutils,

  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libsecret,
  libX11,
  libxcb,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemdLibs,
  xdg-utils,
}:

let
  manifestUrl = "https://cdn-assets.mirasim.ai/mirasim/releases/latest.json";
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "amd64";
      aarch64-linux = "arm64";
    };
    urlTemplate = "https://cdn-assets.mirasim.ai/mirasim/releases/v{version}/Mirasim-{version}-linux-{platform}.deb";
  };

  desktopItem = makeDesktopItem {
    name = "mirasim-desktop";
    desktopName = "Mirasim";
    genericName = "Agent IDE";
    comment = "The Agent IDE that keeps you in the flow — every model, every harness, one window.";
    exec = "mirasim-desktop %U";
    icon = "mirasim-desktop";
    categories = [ "Development" ];
    startupWMClass = "@mirasim/desktop";
  };
in
stdenvNoCC.mkDerivation {
  pname = "mirasim";
  inherit (source) version src;

  nativeBuildInputs = [
    formatelf
    copyDesktopItems
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    gsettings-desktop-schemas
    gtk3
    libdrm
    libgbm
    libX11
    libxcb
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxkbcommon
    nspr
    nss
    pango
    systemdLibs
  ];

  desktopItems = [ desktopItem ];

  # Chromium loads its credential backend dynamically, outside DT_NEEDED.
  runtimeDependencies = [ libsecret ];

  # The bundled ANGLE libEGL.so dlopens the system libEGL.so.1. Patch every
  # ELF's RUNPATH, including shared libraries, so native rendering can start.
  appendRunpaths = [ "${lib.getLib libglvnd}/lib" ];

  unpackPhase = ''
    runHook preUnpack
    ${lib.getExe' bintools "ar"} x $src
    tar xf data.tar.xz
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share/icons $out/share/pixmaps
    cp -a opt/Mirasim $out/lib/Mirasim
    cp -a usr/share/icons/hicolor $out/share/icons/
    # hicolor does not register upstream's only icon size (1024x1024).
    # Provide the unthemed fallback for desktop icon lookup.
    ln -s ../icons/hicolor/1024x1024/apps/mirasim-desktop.png \
      $out/share/pixmaps/mirasim-desktop.png

    makeWrapper "$out/lib/Mirasim/mirasim-desktop" "$out/bin/mirasim-desktop" \
      --suffix PATH : "${
        lib.makeBinPath [
          coreutils
          xdg-utils
        ]
      }" \
      --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";

    updater = mkUpdater {
      kind = "manifest-checksums";
      versionSource = {
        type = "json";
        url = manifestUrl;
        # The top-level version also includes builds outside the stable channel.
        path = "stable.linux.version";
      };
      inherit manifestUrl;
      checksumPath = "stable.linux.deb.{platform}.sha256";
      platforms = {
        x86_64-linux = "x64";
        aarch64-linux = "arm64";
      };
    };
  };

  meta = with lib; {
    description = "The team workspace for coding agents";
    homepage = "https://mirasim.ai";
    changelog = "https://mirasim.ai/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ bet4it ];
    mainProgram = "mirasim-desktop";
    platforms = source.platforms;
  };
}
