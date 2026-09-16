{
  lib,
  stdenv,
  fetchurl,
  formatelf,
  gcc-unwrapped,
  dpkg,
  makeWrapper,
  codesignCheckHook,
  makeDesktopItem,
  copyDesktopItems,
  # Runtime dependencies for Linux
  alsa-lib,
  cairo,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk-layer-shell,
  libayatana-appindicator,
  libsoup_3,
  openblas,
  openssl,
  vulkan-loader,
  webkitgtk_4_1,
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
    aarch64-darwin = fetchurl {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_aarch64.app.tar.gz";
      hash = hashes.aarch64-darwin;
    };
  };

  src =
    srcs.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}. Supported systems: x86_64-linux, aarch64-darwin");

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
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      formatelf
      dpkg
      copyDesktopItems
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      makeWrapper
    ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gcc-unwrapped.lib
    alsa-lib
    cairo
    gdk-pixbuf
    glib
    gtk3
    gtk-layer-shell
    libsoup_3
    openblas
    openssl
    vulkan-loader
    webkitgtk_4_1
  ];

  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    libayatana-appindicator
  ];

  desktopItems = lib.optionals stdenv.hostPlatform.isLinux [ desktopItem ];

  unpackPhase =
    if stdenv.hostPlatform.isLinux then
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
    if stdenv.hostPlatform.isLinux then
      ''
        runHook preInstall

        install -Dm755 usr/bin/handy $out/bin/handy

        # Bundled libs go in a private dir, not $out/lib, to avoid clashing
        # with identically named libraries from other packages (e.g.
        # whisper-cpp's libggml-cpu-cascadelake.so) in shared profiles.
        # The autoPatchelf hook (formatelf) rewrites the RPATHs to find them.
        mkdir -p $out/lib/handy
        cp -a usr/lib/Handy/*.so* $out/lib/handy/

        mkdir -p $out/lib/Handy/resources
        cp -r usr/lib/Handy/resources/* $out/lib/Handy/resources/

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

        mkdir -p $out/bin
        makeWrapper $out/Applications/Handy.app/Contents/MacOS/Handy $out/bin/handy

        runHook postInstall
      '';

  # GUI-only Tauri app: no versionCheckHook, it would block starting the GUI.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ codesignCheckHook ];
  codesignTeamId = "UWFLB4GC25";
  codesignSources = [ srcs.aarch64-darwin ];

  passthru.category = "Voice & Transcription";

  meta = with lib; {
    description = "Fast and accurate local transcription app using AI models";
    homepage = "https://handy.computer/";
    changelog = "https://github.com/cjpais/Handy/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "handy";
  };
}
