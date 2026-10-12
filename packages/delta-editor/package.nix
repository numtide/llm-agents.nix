{
  lib,
  stdenv,
  flake,
  mkUpdater,
  platformSource,
  formatelf,
  makeWrapper,
  unzip,
  desktop-file-utils,
  versionCheckHook,
  versionCheckHomeHook,
  codesignCheckHook,

  # Directly linked (DT_NEEDED). libunwind comes from the bundle.
  libxcb,
  libxkbcommon,

  # Loaded at runtime via dlopen; list taken from zed-industries/delta-nix.
  alsa-lib,
  fontconfig,
  freetype,
  libglvnd,
  libx11,
  libxcb-cursor,
  libxcb-image,
  libxcb-keysyms,
  libxcb-render-util,
  libxcb-util,
  libxcb-wm,
  libxcursor,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  openssl,
  vulkan-loader,
  wayland,
  zlib,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux.file = "delta-linux-x86_64.tar.gz";
      aarch64-linux.file = "delta-linux-aarch64.tar.gz";
      aarch64-darwin.file = "macos/aarch64/Delta.app.zip";
    };
    urlTemplate = "https://releases.delta.dev/releases/stable/{version}/{file}";
  };

  runtimeLibs = [
    stdenv.cc.cc.lib
    alsa-lib
    fontconfig
    freetype
    libglvnd
    libx11
    libxcb
    libxcb-cursor
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-util
    libxcb-wm
    libxcursor
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    openssl
    vulkan-loader
    wayland
    zlib
  ];

  updateExplanation = "Delta is managed by Nix; update the package to install a newer release.";
in
stdenv.mkDerivation {
  pname = "delta-editor";
  inherit (source) version src;

  nativeBuildInputs = [
    makeWrapper
    unzip
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    formatelf
    desktop-file-utils
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libxcb
    libxkbcommon
  ];

  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux runtimeLibs;

  sourceRoot = if stdenv.hostPlatform.isDarwin then "." else "Delta";

  dontConfigure = true;
  dontBuild = true;
  # stripping would invalidate the darwin Developer ID signature.
  dontStrip = true;
  dontFixup = stdenv.hostPlatform.isDarwin;

  installPhase =
    if stdenv.hostPlatform.isDarwin then
      ''
        runHook preInstall

        mkdir -p $out/Applications $out/bin
        cp -a Delta.app $out/Applications/Delta.app
        makeWrapper $out/Applications/Delta.app/Contents/MacOS/delta $out/bin/delta \
          --set DELTA_UPDATE_EXPLANATION ${lib.escapeShellArg updateExplanation}

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        appDir=$out/libexec/delta
        mkdir -p $appDir $out/bin $out/share/applications
        cp -a bin lib $appDir/
        cp -a share/icons $out/share/icons

        # the bundled builds expect /usr/share/X11/xkb; nixpkgs' embed the
        # matching xkeyboard-config store path.
        rm $appDir/lib/libxkbcommon.so.0 $appDir/lib/libxkbcommon-x11.so.0

        # transitive dlopen calls (the Vulkan ICD chain) ignore the RUNPATH.
        for bin in delta delta-app; do
          makeWrapper $appDir/bin/$bin $out/bin/$bin \
            --prefix LD_LIBRARY_PATH : "$appDir/lib:${lib.makeLibraryPath runtimeLibs}" \
            --set DELTA_UPDATE_EXPLANATION ${lib.escapeShellArg updateExplanation}
        done

        substitute share/applications/dev.zed.Delta.desktop \
          $out/share/applications/dev.zed.Delta.desktop \
          --replace-fail "Exec=delta " "Exec=$out/bin/delta "

        runHook postInstall
      '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
    codesignCheckHook
  ];
  # the delta CLI reports a stale version (0.17.0 in the 0.19.2 release).
  versionCheckProgram = "${placeholder "out"}/${
    if stdenv.hostPlatform.isDarwin then "Applications/Delta.app/Contents/MacOS" else "bin"
  }/delta-app";
  codesignTeamId = "MQ55VZLNZQ";
  codesignSources = source.darwinSrcs;

  preInstallCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    desktop-file-validate $out/share/applications/*.desktop
  '';

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater (
    source.updater
    // {
      versionSource = {
        type = "text";
        url = "https://delta.dev/api/releases/stable/latest/asset?asset=delta&os=linux&arch=x86_64";
        regex = ''"version": *"([^"]+)"'';
      };
    }
  );

  meta = {
    description = "AI-native code editor from the makers of Zed (beta)";
    homepage = "https://delta.dev";
    changelog = "https://github.com/zed-industries/delta-nix/releases/tag/v${source.version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ zimbatm ];
    mainProgram = "delta";
    inherit (source) platforms;
  };
}
