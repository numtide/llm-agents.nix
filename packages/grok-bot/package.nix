{
  mkUpdater,
  fetchurl,
  lib,
  flake,
  formatelf,
  makeWrapper,
  stdenvNoCC,
  bintools,
  copyDesktopItems,
  makeDesktopItem,
  unzip,
  codesignCheckHook,
  mkCodesignCheck,

  # Directly linked (DT_NEEDED); formatelf/autoPatchelf resolves these from
  # buildInputs and fails the build if any are missing.
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
  libdrm,
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

  # Provides libudev without pulling the whole systemd closure.
  systemdLibs,

  # Loaded at runtime via dlopen.
  libglvnd,
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
  pname = "grok-bot";

  # update.py refreshes version/buildId/urls/hashes from Cursor's update feed.
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version urls hashes;

  platform = stdenvNoCC.hostPlatform.system;

  srcFor =
    system:
    fetchurl {
      url = urls.${system} or (throw "Unsupported system: ${system}");
      hash = hashes.${system} or (throw "Unsupported system: ${system}");
    };

  src = srcFor platform;

  teamId = "DCNK4UB866";

  desktopItem = makeDesktopItem {
    name = "grok-bot";
    desktopName = "Grok Bot";
    genericName = "AI Assistant";
    comment = "AI teammates that finish the work";
    exec = "grok-bot %U";
    icon = "grok-bot";
    categories = [ "Development" ];
    startupNotify = true;
    startupWMClass = "grok-bot";
    # sand:// is the historical login-redirect scheme; grokbot:// is current.
    mimeTypes = [
      "x-scheme-handler/grokbot"
      "x-scheme-handler/sand"
    ];
  };

  passthru = {
    category = "AI Assistants";
    updater = mkUpdater { kind = "script"; };
    tests.codesign = mkCodesignCheck {
      name = pname;
      inherit teamId;
      srcs = [ (srcFor "aarch64-darwin") ];
    };
  };

  meta = with lib; {
    description = "Grok Bot desktop agent — AI teammates that finish the work";
    homepage = "https://x.ai/bot";
    downloadPage = "https://cursor.com/download/bot";
    # No versioned changelog; upstream publishes via the download feed.
    changelog = "https://x.ai/bot";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ jonjitsu ];
    mainProgram = "grok-bot";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };

  linux = stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      src
      meta
      passthru
      ;

    # Prebuilt Electron — stripping buys nothing and corrupts the binary.
    dontStrip = true;

    nativeBuildInputs = [
      formatelf
      copyDesktopItems
      makeWrapper
    ];

    buildInputs = [
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
      libdrm
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

    # dlopen()ed at runtime, so not discoverable from DT_NEEDED. libglvnd goes on
    # the wrapper's LD_LIBRARY_PATH instead: ANGLE's bundled libEGL.so dlopen()s
    # the native libEGL.so.1, and RUNPATH on that object alone does not survive
    # fixup (see orca).
    runtimeDependencies = [
      libayatana-appindicator
      libnotify
      libpulseaudio
      libsecret
      libXcursor
      pipewire
      wayland
    ];

    desktopItems = [ desktopItem ];

    unpackPhase = ''
      runHook preUnpack
      ${lib.getExe' bintools "ar"} x $src
      tar xf data.tar.*
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/bin $out/share
      cp -a "opt/Grok Bot" $out/lib/grok-bot
      cp -a usr/share/icons $out/share/icons

      # chrome-sandbox needs setuid root, which a store path can never have.
      # Chromium falls back to user namespaces, as with other Electron apps here.
      rm -f $out/lib/grok-bot/chrome-sandbox

      chmod +x $out/lib/grok-bot/grok-bot

      # CHROME_DESKTOP: Electron's protocol registration must target our
      # desktop id, not a guessed "electron.desktop".
      # --no-sandbox: upstream's Electron build crash-loops sandboxed webview
      # renderers (FATAL:platform_shared_memory_region_posix.cc); they already
      # disable the sandbox for most other processes.
      makeWrapper $out/lib/grok-bot/grok-bot $out/bin/grok-bot \
        --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libglvnd ]} \
        --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
        --set-default CHROME_DESKTOP grok-bot.desktop \
        --add-flags "--no-sandbox"

      runHook postInstall
    '';

    # No versionCheckHook: GUI-only desktop app, --version would start Electron.
  };

  # macOS ships as a signed and notarized zip containing Grok Bot.app. It is
  # installed as-is: fixup could modify sealed files and invalidate Anysphere's
  # Developer ID signature.
  darwin = stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      src
      meta
      passthru
      ;

    nativeBuildInputs = [
      makeWrapper
      unzip
    ];

    # The default unpack phase would cd into the single top-level .app it
    # detects; keep the extraction root so installPhase can copy the bundle.
    sourceRoot = ".";

    dontFixup = true;

    doInstallCheck = true;
    nativeInstallCheckInputs = [ codesignCheckHook ];
    codesignTeamId = teamId;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications $out/bin
      cp -a "Grok Bot.app" "$out/Applications/Grok Bot.app"

      # A symlink would make Electron resolve its bundle from bin/ and fail to
      # find its helper apps; the wrapper execs the binary inside the bundle.
      makeWrapper "$out/Applications/Grok Bot.app/Contents/MacOS/Grok Bot" $out/bin/grok-bot

      runHook postInstall
    '';
  };
in
if stdenvNoCC.hostPlatform.isDarwin then darwin else linux
