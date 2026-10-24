{
  lib,
  flake,
  platformSource,
  stdenvNoCC,
  bintools,
  formatelf,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  undmg,
  codesignCheckHook,
  mkCodesignCheck,

  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  glib,
  gtk3,
  libX11,
  libxcb,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxkbcommon,
  libgbm,
  nspr,
  nss,
  pango,
  systemdLibs,

  libglvnd,
  vulkan-loader,
  libsecret,
  libnotify,
  libpulseaudio,
  libayatana-appindicator,
  libXcursor,
  pipewire,
  wayland,
  xdg-utils,

  adwaita-icon-theme,
  gsettings-desktop-schemas,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-amd64.deb";
      aarch64-linux = "linux-arm64.deb";
      aarch64-darwin = "mac-arm64.dmg";
    };
    urlTemplate = "https://opencode.ai/files/bin/{version}/opencode-desktop-{platform}";
  };

  desktopItem = makeDesktopItem {
    name = "opencode2-desktop";
    desktopName = "OpenCode 2";
    comment = "Open source AI coding agent";
    exec = "opencode2-desktop %U";
    icon = "opencode2-desktop";
    startupWMClass = "ai.opencode.desktop";
    categories = [ "Development" ];
    mimeTypes = [ "x-scheme-handler/opencode" ];
  };

  inherit (stdenvNoCC.hostPlatform) isLinux;

  # From `codesign -dv --verbose=4 OpenCode.app` on the upstream DMG:
  # Developer ID Application: Anomaly Innovations, Inc. (5NZ4Q7NXJ4)
  teamId = "5NZ4Q7NXJ4";
in
stdenvNoCC.mkDerivation {
  pname = "opencode2-desktop";
  inherit (source) version src;

  dontStrip = true;

  nativeBuildInputs =
    lib.optionals stdenvNoCC.hostPlatform.isDarwin [ undmg ]
    ++ lib.optionals isLinux [
      formatelf
      copyDesktopItems
      makeWrapper
    ];

  buildInputs = lib.optionals isLinux [
    adwaita-icon-theme
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    gsettings-desktop-schemas
    gtk3
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

  runtimeDependencies = lib.optionals isLinux [
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    libXcursor
    pipewire
    wayland
  ];

  appendRunpaths = lib.optionals isLinux (
    map (package: "${lib.getLib package}/lib") [
      libglvnd
      vulkan-loader
    ]
  );

  desktopItems = lib.optional isLinux desktopItem;

  sourceRoot = lib.optionalString (!isLinux) ".";

  unpackPhase = lib.optionalString isLinux ''
    runHook preUnpack
    ${lib.getExe' bintools "ar"} x $src
    tar xf data.tar.xz
    runHook postUnpack
  '';

  installPhase =
    if isLinux then
      ''
        runHook preInstall

        mkdir -p $out/libexec $out/bin $out/share/icons/hicolor
        cp -a opt/OpenCode $out/libexec/opencode2-desktop

        for size in 32 64 128; do
          install -Dm644 \
            usr/share/icons/hicolor/''${size}x''${size}/apps/ai.opencode.png \
            $out/share/icons/hicolor/''${size}x''${size}/apps/opencode2-desktop.png
        done

        makeWrapper $out/libexec/opencode2-desktop/ai.opencode \
          $out/bin/opencode2-desktop \
          --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
          --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p "$out/Applications" $out/bin
        cp -R OpenCode.app "$out/Applications/OpenCode 2.app"
        ln -s "$out/Applications/OpenCode 2.app/Contents/MacOS/OpenCode" \
          $out/bin/opencode2-desktop

        runHook postInstall
      '';

  doInstallCheck = true;
  nativeInstallCheckInputs = lib.optionals stdenvNoCC.hostPlatform.isDarwin [ codesignCheckHook ];
  codesignTeamId = teamId;

  passthru.category = "AI Coding Agents";
  passthru.tests.codesign = mkCodesignCheck {
    name = "opencode2-desktop";
    inherit teamId;
    srcs = source.darwinSrcs;
  };

  meta = with lib; {
    description = "OpenCode 2 desktop client";
    homepage = "https://opencode.ai";
    changelog = "https://github.com/anomalyco/opencode/commits/v2";
    downloadPage = "https://opencode.ai/v2/docs#desktop";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ iainlane ];
    mainProgram = "opencode2-desktop";
    platforms = source.platforms;
  };
}
