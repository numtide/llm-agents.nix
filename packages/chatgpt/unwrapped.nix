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
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  gitMinimal,
  glib,
  gtk3,
  libGL,
  libgbm,
  libnotify,
  libpulseaudio,
  libsecret,
  libusb1,
  libxkbcommon,
  nspr,
  nss,
  openssl,
  pango,
  pciutils,
  pipewire,
  qt6,
  systemd,
  tpm2-tss,
  vulkan-loader,
  wayland,
  xdg-utils,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
  libxcursor,
  # Qt6 shim for Plasma 6 integration; Chromium falls back to GTK without it.
  withQt ? false,
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
  dontWrapQtApps = true;

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

  buildInputs =
    lib.optionals isLinux [
      alsa-lib
      at-spi2-core
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      libgbm
      libusb1
      libxkbcommon
      nspr
      nss
      openssl
      pango
      stdenv.cc.cc.lib
      systemd
      tpm2-tss
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
    ]
    ++ lib.optionals (isLinux && withQt) [ qt6.qtbase ];

  # Electron loads these at runtime rather than linking them directly. Put
  # them on each ELF object's RPATH without leaking a broad LD_LIBRARY_PATH
  # into Electron's Node and Chromium children.
  runtimeDependencies = lib.optionals isLinux [
    libGL
    libgbm
    libnotify
    libsecret
    libpulseaudio
    libxcursor
    pciutils
    pipewire
    vulkan-loader
    wayland
  ];

  # The archive includes musl, glibc, and Android prebuilds for a few Node
  # modules. NixOS uses the glibc variants, so the other runtimes are
  # intentionally absent.
  autoPatchelfIgnoreMissingDeps = lib.optionals isLinux [
    "libc++_shared.so"
    "libc.musl-x86_64.so.1"
    "liblog.so"
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

        # Plasma 5 is gone from nixpkgs.
        rm "$out/lib/chatgpt/libqt5_shim.so"
        ${lib.optionalString (!withQt) ''rm "$out/lib/chatgpt/libqt6_shim.so"''}

        # The bundled loader does not search /run/opengl-driver for ICDs.
        ln -sf ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 "$out/lib/chatgpt/libvulkan.so.1"

        # See patch-asar.py for the NixOS-specific source patches.
        python3 ${./patch-asar.py} "$out/lib/chatgpt/resources/app.asar"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p "$out/Applications"
        mv ChatGPT.app "$out/Applications/"

        runHook postInstall
      '';

  # gappsWrapperArgs is only populated by wrapGAppsHook3 after installPhase.
  # Host Qt plugins may not match the shim's Qt ABI.
  preFixup = lib.optionalString isLinux ''
    wrapProgram "$out/lib/chatgpt/ChatGPT" \
      "''${gappsWrapperArgs[@]}" \
      ${lib.optionalString withQt "--unset QT_PLUGIN_PATH --unset QT_QPA_PLATFORM_PLUGIN_PATH"} \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          coreutils
          gitMinimal
          xdg-utils
        ]
      }
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
