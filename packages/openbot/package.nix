{
  lib,
  flake,
  platformSource,
  mkUpdater,
  stdenvNoCC,
  appimageTools,
  unzip,
  formatelf,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
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
  libXi,
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
        suffix = "x86_64.AppImage";
      };
      aarch64-linux = {
        suffix = "arm64.AppImage";
      };
      aarch64-darwin = {
        suffix = "arm64.zip";
      };
    };
    urlTemplate = "https://github.com/nightly-labs/openbot/releases/download/v{version}/OpenBot-{version}-{suffix}";
  };
  # Akudama GmbH signs the app. The bundled cua-driver (computer use) keeps the
  # signature of its publisher, Cua AI.
  teamId = "ZTRDTUL87R YCK386LBJ7";
  inherit (stdenvNoCC.hostPlatform) isLinux;

  contents = appimageTools.extract {
    pname = "openbot";
    inherit (source) version src;
    # The bundled Sunshine needs libminiupnpc.so.17, which nixpkgs does not
    # ship. Without the runtime directory OpenBot reports remote desktop as
    # unavailable instead of failing to start it.
    postExtract = ''
      rm -rf $out/resources/remote-desktop-runtime
    '';
  };

  # The AppImage's desktop entry runs `AppRun --no-sandbox`. Start the Electron
  # binary directly so Chromium keeps its sandbox.
  desktopItem = makeDesktopItem {
    name = "openbot";
    desktopName = "OpenBot";
    comment = "Local-first multi-agent desktop workspace";
    exec = "openbot %U";
    icon = "openbot";
    categories = [ "Development" ];
    startupWMClass = "openbot";
    mimeTypes = [ "x-scheme-handler/openbot" ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "openbot";
  inherit (source) version;
  src = if isLinux then contents else source.src;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals (!isLinux) [ unzip ]
  ++ lib.optionals isLinux [
    formatelf
    copyDesktopItems
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
    # cua-driver (computer use)
    libXi
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

  # Chromium dlopen()s the system GL/Vulkan loaders itself.
  appendRunpaths = lib.optionals isLinux (
    map (p: "${lib.getLib p}/lib") [
      libglvnd
      vulkan-loader
    ]
  );

  desktopItems = lib.optionals isLinux [ desktopItem ];

  sourceRoot = lib.optionalString (!isLinux) ".";

  installPhase =
    if isLinux then
      ''
        runHook preInstall

        # Keep the AppImage layout so libffmpeg.so and resources/ resolve
        # next to the binary. usr/lib holds the AppImage's own copies of
        # system libraries, which nixpkgs provides instead. openbot.png links
        # into usr/.
        mkdir -p $out/libexec/openbot $out/bin $out/share/pixmaps
        cp -a . $out/libexec/openbot
        rm -rf $out/libexec/openbot/{usr,AppRun,.DirIcon,openbot.desktop,openbot.png}

        # chrome-sandbox needs setuid root, which a store path can never have.
        # Electron falls back to user namespaces.
        rm -f $out/libexec/openbot/chrome-sandbox

        # The AppImage ships only a 1600x1600 icon, a size no icon theme lists.
        install -Dm444 openbot.png $out/share/pixmaps/openbot.png

        # OpenBot turns its updater off when it runs from the Nix store; on
        # Linux it updates itself only from an AppImage ($APPIMAGE).
        makeWrapper "$out/libexec/openbot/openbot" "$out/bin/openbot" \
          --set-default CHROME_DESKTOP openbot.desktop \
          --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
          --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall
        mkdir -p $out/Applications $out/bin
        cp -R OpenBot.app $out/Applications/
        # Electron finds its helper apps from argv[0], so a symlink would
        # start without them.
        makeWrapper $out/Applications/OpenBot.app/Contents/MacOS/OpenBot $out/bin/openbot
        runHook postInstall
      '';

  # resources/hosting holds scripts that OpenBot installs on remote servers,
  # so their shebangs must keep the FHS paths.
  dontPatchShebangs = true;
  dontStrip = true;
  # Fixup would change files inside the signed and notarized app bundle.
  dontFixup = !isLinux;

  passthru = {
    category = "AI Coding Agents";
    tests.codesign = mkCodesignCheck {
      name = "openbot";
      inherit teamId;
      srcs = source.darwinSrcs;
    };

    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "github";
          owner = "nightly-labs";
          repo = "openbot";
        };
      }
    );
  };

  meta = with lib; {
    description = "Local-first multi-agent desktop workspace for Codex, Claude, Grok and other coding agents";
    homepage = "https://github.com/nightly-labs/openbot";
    changelog = "https://github.com/nightly-labs/openbot/releases/tag/v${source.version}";
    # PolyForm Noncommercial 1.0.0
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ NorbertBodziony ];
    mainProgram = "openbot";
    platforms = source.platforms;
  };
}
