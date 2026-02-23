{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc-unwrapped,
  dpkg,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  # Runtime dependencies for Linux
  alsa-lib,
  alsa-utils,
  cairo,
  dotool,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk-layer-shell,
  libayatana-appindicator,
  libsoup_3,
  openssl,
  pulseaudio,
  vulkan-loader,
  webkitgtk_4_1,
  wireplumber,
  wl-clipboard,
  wtype,
  xdotool,
  ydotool,
}:

let
  pname = "handy";
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  # Linux uses deb packages, macOS uses app tarballs
  srcs = {
    x86_64-linux = fetchurl {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.deb";
      hash = hashes.x86_64-linux;
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_x64.app.tar.gz";
      hash = hashes.x86_64-darwin;
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_aarch64.app.tar.gz";
      hash = hashes.aarch64-darwin;
    };
  };

  src =
    srcs.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}. Supported systems: x86_64-linux, x86_64-darwin, aarch64-darwin");

  desktopItem = makeDesktopItem {
    name = "handy";
    desktopName = "Handy";
    comment = "Fast and accurate local transcription app";
    exec = "handy";
    icon = "handy";
    categories = [
      "Audio"
      "AudioVideo"
      "Utility"
    ];
    startupNotify = true;
  };

  runtimeToolPath = lib.makeBinPath [
    alsa-utils
    dotool
    pulseaudio
    wireplumber
    wl-clipboard
    wtype
    xdotool
    ydotool
  ];
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs =
    lib.optionals stdenv.isLinux [
      autoPatchelfHook
      copyDesktopItems
      dpkg
      makeWrapper
    ]
    ++ lib.optionals stdenv.isDarwin [
      makeWrapper
    ];

  buildInputs = lib.optionals stdenv.isLinux [
    gcc-unwrapped.lib
    alsa-lib
    cairo
    gdk-pixbuf
    glib
    gtk3
    gtk-layer-shell
    libsoup_3
    openssl
    vulkan-loader
    webkitgtk_4_1
  ];

  runtimeDependencies = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    libayatana-appindicator
  ];

  desktopItems = lib.optionals stdenv.isLinux [ desktopItem ];

  unpackPhase =
    if stdenv.isLinux then
      ''
        runHook preUnpack

        dpkg -x $src .

        runHook postUnpack
      ''
    else
      ''
        runHook preUnpack

        mkdir -p ./unpacked
        tar -xzf $src -C ./unpacked

        runHook postUnpack
      '';

  installPhase =
    if stdenv.isLinux then
      ''
        runHook preInstall

        # Install the binary
        install -Dm755 usr/bin/handy $out/bin/handy

        # Install resources
        mkdir -p $out/lib/Handy/resources
        cp -r usr/lib/Handy/resources/* $out/lib/Handy/resources/

        # Install icons
        mkdir -p $out/share/icons/hicolor
        if [ -d usr/share/icons/hicolor ]; then
          cp -r usr/share/icons/hicolor/* $out/share/icons/hicolor/
        fi

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p $out/Applications
        cp -r ./unpacked/Handy.app $out/Applications/

        # Create a wrapper script in bin
        mkdir -p $out/bin
        makeWrapper $out/Applications/Handy.app/Contents/MacOS/Handy $out/bin/handy \
          --prefix PATH : "${runtimeToolPath}"

        runHook postInstall
      '';

  postInstall = lib.optionalString stdenv.isLinux ''
    wrapProgram $out/bin/handy \
      --prefix PATH : "${runtimeToolPath}"
  '';

  # GUI-only Tauri app - no CLI version support, would block trying to start GUI
  doInstallCheck = false;

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Fast and accurate local transcription app using AI models";
    homepage = "https://handy.computer/";
    changelog = "https://github.com/cjpais/Handy/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ ];
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "handy";
  };
}
