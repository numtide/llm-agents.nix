{
  lib,
  flake,
  stdenv,
  fetchurl,
  bubblewrap,
  coreutils,
  dpkg,
  formatelf,
  makeWrapper,
  python3,
  unzip,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  gitMinimal,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libGL,
  libdrm,
  libgbm,
  libnotify,
  libpulseaudio,
  libsecret,
  libusb1,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  qt5,
  qt6,
  systemd,
  wayland,
  xdg-utils,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
}:

let
  sourceData = builtins.fromJSON (builtins.readFile ./hashes.json);
  platform = stdenv.hostPlatform.system;
  isLinux = stdenv.hostPlatform.isLinux;
  isDarwin = stdenv.hostPlatform.isDarwin;
  source = sourceData.sources.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "chatgpt-unwrapped";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  dontStrip = true;
  dontWrapGApps = true;

  nativeBuildInputs =
    lib.optionals isLinux [
      python3
      formatelf
      dpkg
      makeWrapper
      wrapGAppsHook3
    ]
    ++ lib.optionals isDarwin [
      unzip
    ];

  buildInputs = lib.optionals isLinux [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gsettings-desktop-schemas
    gtk3
    libGL
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libusb1
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    wayland
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];

  # Electron loads these at runtime rather than linking them directly. Put
  # them on each ELF object's RPATH without leaking a broad LD_LIBRARY_PATH
  # into Electron's Node and Chromium children.
  runtimeDependencies = lib.optionals isLinux [
    libGL
    libgbm
    libnotify
    libsecret
    libpulseaudio
    pipewire
    wayland
  ];

  # The archive includes musl, glibc, and Android prebuilds for a few Node
  # modules. NixOS uses the glibc variants, so the other runtimes are
  # intentionally absent.
  # The Qt shims are optional and selected dynamically, so autoPatchelf cannot
  # resolve both of their runtimes during its direct dependency pass. Their
  # version-specific RPATHs are added in postFixup below.
  autoPatchelfIgnoreMissingDeps = lib.optionals isLinux [
    "libc++_shared.so"
    "libc.musl-x86_64.so.1"
    "liblog.so"
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  unpackPhase =
    if isLinux then
      ''
        runHook preUnpack
        dpkg-deb -x "$src" .
        runHook postUnpack
      ''
    else
      ''
        runHook preUnpack
        unzip -q "$src"
        runHook postUnpack
      '';

  installPhase =
    if isLinux then
      ''
        runHook preInstall

        mkdir -p "$out/bin" "$out/lib" "$out/share"
        cp -r usr/lib/chatgpt "$out/lib/"
        cp -r usr/share/applications usr/share/pixmaps "$out/share/"
        ln -s ../lib/chatgpt/codex-launcher "$out/bin/chatgpt"

        # See patch-asar.py for the NixOS-specific source patches.
        python3 ${./patch-asar.py} "$out/lib/chatgpt/resources/app.asar"

        # Host Qt plugins can use a different private ABI than our Qt shims.
        # Let each shim discover plugins from its own Qt installation.
        wrapProgram "$out/lib/chatgpt/ChatGPT" \
          "''${gappsWrapperArgs[@]}" \
          --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH" \
          --unset QT_PLUGIN_PATH \
          --unset QT_QPA_PLATFORM_PLUGIN_PATH \
          --prefix PATH : ${
            lib.makeBinPath [
              bubblewrap
              coreutils
              gitMinimal
              xdg-utils
            ]
          }

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p "$out/Applications"
        mv ChatGPT.app "$out/Applications/"

        runHook postInstall
      '';

  postFixup = lib.optionalString isLinux ''
    patchelf --add-rpath ${lib.makeLibraryPath [ qt5.qtbase ]} \
      "$out/lib/chatgpt/libqt5_shim.so"
    patchelf --add-rpath ${lib.makeLibraryPath [ qt6.qtbase ]} \
      "$out/lib/chatgpt/libqt6_shim.so"
  '';

  # Any modification forces ad-hoc re-signing, which drops OpenAI's keychain
  # entitlements and breaks Remote Control (#9315).
  dontFixup = isDarwin;

  meta = with lib; {
    description = "Desktop application for ChatGPT and Codex";
    homepage = "https://developers.openai.com/codex/app";
    changelog = "https://learn.chatgpt.com/docs/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ whazor ];
    mainProgram = "chatgpt";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
