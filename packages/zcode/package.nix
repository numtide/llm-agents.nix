{
  lib,
  flake,
  platformSource,
  mkUpdater,
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

  # libs-only build of systemd to avoid pulling the whole systemd closure
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

  # Needed for XDG_ICON_DIRS and GSETTINGS_SCHEMAS_PATH.
  adwaita-icon-theme,
  gsettings-desktop-schemas,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = {
        dir = "linux-x64";
        file = "linux-x64.deb";
      };
      aarch64-linux = {
        dir = "linux-arm64";
        file = "linux-arm64.deb";
      };
      aarch64-darwin = {
        dir = "macos-arm64";
        file = "mac-arm64.dmg";
      };
    };
    urlTemplate = "https://cdn-zcode.z.ai/zcode/electron/releases/{version}/{dir}/ZCode-{version}-{file}";
  };
  teamId = "8A5X4JJ39T";

  desktopItem = makeDesktopItem {
    name = "zcode";
    desktopName = "ZCode";
    genericName = "Agentic Development Environment";
    comment = "ZCode Desktop App";
    exec = "zcode %U";
    icon = "zcode";
    categories = [ "Development" ];
    # Electron/Chromium on Linux sets WM_CLASS and Wayland app_id to the lowercase
    # binary name ("zcode"), so window managers match only against this exact value.
    startupWMClass = "zcode";
    mimeTypes = [ "x-scheme-handler/zcode" ];
  };
  inherit (stdenvNoCC.hostPlatform) isLinux;
in
stdenvNoCC.mkDerivation {
  pname = "zcode";
  inherit (source) version src;

  nativeBuildInputs =
    lib.optionals stdenvNoCC.hostPlatform.isDarwin [ undmg ]
    ++ lib.optionals isLinux [
      formatelf
      copyDesktopItems
      makeWrapper
    ];

  doInstallCheck = true;
  nativeInstallCheckInputs = lib.optionals stdenvNoCC.hostPlatform.isDarwin [ codesignCheckHook ];
  codesignTeamId = teamId;

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

  # dlopen()ed by the main binary at runtime, so not discoverable from
  # DT_NEEDED. List them here to put them on its RUNPATH.
  runtimeDependencies = lib.optionals isLinux [
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    libXcursor
    pipewire
    wayland
  ];

  # The bundled ANGLE libEGL.so/libGLESv2.so dlopen() the system GL/Vulkan
  # loaders themselves. runtimeDependencies only reaches executables, while
  # appendRunpaths is applied to every patched ELF.
  appendRunpaths = lib.optionals isLinux (
    map (p: "${lib.getLib p}/lib") [
      libglvnd
      vulkan-loader
    ]
  );

  desktopItems = [ desktopItem ];

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

        # Keep the upstream opt/ZCode layout so bundled libs (e.g. libffmpeg.so)
        # resolve next to the main binary.
        mkdir -p $out/lib $out/bin $out/share/pixmaps
        cp -a opt/ZCode $out/lib/ZCode
        cp -a usr/share/icons $out/share/icons
        ln -s $out/share/icons/hicolor/512x512/apps/zcode.png $out/share/pixmaps/zcode.png

        chmod +x $out/lib/ZCode/zcode

        makeWrapper "$out/lib/ZCode/zcode" "$out/bin/zcode" \
          --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
          --prefix XDG_DATA_DIRS : "$out/share:$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall
        mkdir -p $out/Applications $out/bin
        cp -R ZCode.app $out/Applications/
        ln -s $out/Applications/ZCode.app/Contents/MacOS/ZCode $out/bin/zcode
        runHook postInstall
      '';

  passthru = {
    category = "AI Coding Agents";
    tests.codesign = mkCodesignCheck {
      name = "zcode";
      inherit teamId;
      srcs = source.darwinSrcs;
    };

    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "text";
          url = "https://zcode.z.ai/en";
          # Anchor on the pluginDownload key that follows the download section
          # so a changelog entry cannot shadow the latest version.
          regex = ''\\"version\\":\\"([0-9]+\.[0-9]+\.[0-9]+)\\"},\\"pluginDownload\\"'';
        };
      }
    );
  };

  meta = with lib; {
    description = "Agentic development environment (ADE) by Z.ai";
    homepage = "https://zcode.z.ai";
    changelog = "https://zcode.z.ai/en/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ imxyy1soope1 ];
    mainProgram = "zcode";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
