{
  lib,
  flake,
  stdenv,
  fetchurl,
  appimageTools,
  unzip,
  makeWrapper,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  pname = "auto-claude";

  platform = stdenv.hostPlatform.system;

  sources = {
    x86_64-linux = {
      url = "https://github.com/AndyMik90/Auto-Claude/releases/download/v${version}/Auto-Claude-${version}-linux-x86_64.AppImage";
      hash = hashes.x86_64-linux;
    };
    x86_64-darwin = {
      url = "https://github.com/AndyMik90/Auto-Claude/releases/download/v${version}/Auto-Claude-${version}-darwin-x64.zip";
      hash = hashes.x86_64-darwin;
    };
    aarch64-darwin = {
      url = "https://github.com/AndyMik90/Auto-Claude/releases/download/v${version}/Auto-Claude-${version}-darwin-arm64.zip";
      hash = hashes.aarch64-darwin;
    };
  };

  src = fetchurl sources.${platform} or (throw "Unsupported system: ${platform}");

  meta = with lib; {
    description = "Autonomous multi-agent coding framework powered by Claude AI";
    homepage = "https://github.com/AndyMik90/Auto-Claude";
    changelog = "https://github.com/AndyMik90/Auto-Claude/releases/tag/v${version}";
    license = licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ xorilog ];
    mainProgram = "auto-claude";
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };

  linux = appimageTools.wrapType2 {
    inherit
      pname
      version
      src
      meta
      ;

    extraInstallCommands =
      let
        appimageContents = appimageTools.extractType2 { inherit pname version src; };
      in
      ''
        # Install desktop file if present
        if [ -f "${appimageContents}/auto-claude.desktop" ]; then
          install -Dm644 ${appimageContents}/auto-claude.desktop $out/share/applications/auto-claude.desktop
          substituteInPlace $out/share/applications/auto-claude.desktop \
            --replace-fail 'Exec=AppRun' 'Exec=auto-claude'
        fi

        # Install icons if they exist
        for size in 16 32 48 64 128 256 512; do
          if [ -f "${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/auto-claude.png" ]; then
            install -Dm644 "${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/auto-claude.png" \
              "$out/share/icons/hicolor/''${size}x''${size}/apps/auto-claude.png"
          fi
        done

        # Fallback: install main icon if present
        if [ -f "${appimageContents}/auto-claude.png" ]; then
          install -Dm644 "${appimageContents}/auto-claude.png" "$out/share/icons/hicolor/256x256/apps/auto-claude.png"
        fi
      '';

    passthru.category = "Claude Code Ecosystem";
  };

  darwin = stdenv.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;

    nativeBuildInputs = [
      unzip
      makeWrapper
    ];

    unpackPhase = ''
      runHook preUnpack
      unzip -q $src
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications
      cp -r "Auto-Claude.app" $out/Applications/

      # Create a wrapper script in bin
      mkdir -p $out/bin
      makeWrapper "$out/Applications/Auto-Claude.app/Contents/MacOS/Auto-Claude" $out/bin/auto-claude

      runHook postInstall
    '';

    passthru.category = "Claude Code Ecosystem";
  };
in
if stdenv.hostPlatform.isLinux then linux else darwin
