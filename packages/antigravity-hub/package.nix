{
  lib,
  flake,
  stdenv,
  fetchurl,
  alsa-lib,
  asar,
  at-spi2-atk,
  at-spi2-core,
  atk,
  formatelf,
  cairo,
  copyDesktopItems,
  cups,
  dbus,
  expat,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libGL,
  libgbm,
  libnotify,
  libpulseaudio,
  libsecret,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  makeDesktopItem,
  makeShellWrapper,
  makeWrapper,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  unzip,
  wrapGAppsHook3,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version buildId;
  platformData =
    versionData.platforms.${stdenv.hostPlatform.system}
      or (throw "antigravity-hub: unsupported system ${stdenv.hostPlatform.system}");
  ext = if stdenv.hostPlatform.isDarwin then "zip" else "tar.gz";
in
stdenv.mkDerivation {
  pname = "antigravity-hub";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-hub/${version}-${buildId}/${platformData.platform}/Antigravity.${ext}";
    inherit (platformData) hash;
  };

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      asar
      formatelf
      copyDesktopItems
      makeShellWrapper
      wrapGAppsHook3
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      makeWrapper
      unzip
    ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gsettings-desktop-schemas
    gtk3
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    systemd
  ];

  # Loaded with dlopen() by the main binary, so autoPatchelfHook cannot discover them.
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux (
    map lib.getLib [
      libnotify
      libpulseaudio
      libsecret
      pipewire
    ]
  );

  # The bundled ANGLE libraries (libEGL.so, libGLESv2.so) dlopen() the system GL
  # libraries. runtimeDependencies only applies to executables, so extend the
  # RUNPATH of every patched ELF file instead.
  appendRunpaths = lib.optionals stdenv.hostPlatform.isLinux [ "${lib.getLib libGL}/lib" ];

  # The wrapper is created in postFixup to add the Wayland flags.
  dontWrapGApps = true;

  desktopItems = lib.optionals stdenv.hostPlatform.isLinux [
    (makeDesktopItem {
      name = "antigravity-hub";
      desktopName = "Antigravity";
      comment = "Manage multiple autonomous agents across independent projects";
      exec = "antigravity %U";
      icon = "antigravity";
      categories = [ "Development" ];
      mimeTypes = [ "x-scheme-handler/antigravity" ];
      startupWMClass = "Antigravity";
    })
  ];

  installPhase =
    if stdenv.hostPlatform.isDarwin then
      ''
        runHook preInstall

        mkdir -p $out/Applications/Antigravity.app
        cp -R . $out/Applications/Antigravity.app
        makeWrapper $out/Applications/Antigravity.app/Contents/MacOS/Antigravity $out/bin/antigravity

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p $out/share/antigravity
        cp -r . $out/share/antigravity

        asar extract-file resources/app.asar icon.png
        install -Dm644 icon.png $out/share/icons/hicolor/512x512/apps/antigravity.png

        runHook postInstall
      '';

  # Stripping or patching files inside the app bundle would invalidate its code signature.
  dontFixup = stdenv.hostPlatform.isDarwin;

  # wrapGAppsHook3 provides makeBinaryWrapper, which cannot expand the shell
  # variables in --add-flags, hence makeShellWrapper.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    makeShellWrapper $out/share/antigravity/antigravity $out/bin/antigravity \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
  '';

  passthru = {
    inherit buildId;
    updateScript = ./update.py;
    category = "AI Assistants";
  };

  meta = with lib; {
    description = "Desktop environment for managing multiple autonomous agents across independent projects";
    homepage = "https://antigravity.google";
    changelog = "https://antigravity.google/changelog";
    downloadPage = "https://antigravity.google/download";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames versionData.platforms;
    mainProgram = "antigravity";
    maintainers = with maintainers; [
      sinics
    ];
  };
}
