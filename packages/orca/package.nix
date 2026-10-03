{
  lib,
  flake,
  platformSource,
  mkUpdater,
  stdenvNoCC,
  bintools,
  unzip,
  formatelf,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,

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
  libsecret,
  libnotify,
  libpulseaudio,
  libayatana-appindicator,
  libXcursor,
  pipewire,
  wayland,

  # `orca serve` and the computer-use surface shell out to these; the deb
  # declares them as Depends.
  git,
  xclip,
  xdotool,
  xdg-utils,
  xvfb,
  xvfb-run,

  # Needed for XDG_ICON_DIRS and GSETTINGS_SCHEMAS_PATH.
  adwaita-icon-theme,
  gsettings-desktop-schemas,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = {
        prefix = "orca-ide_";
        suffix = "_amd64.deb";
      };
      aarch64-linux = {
        prefix = "orca-ide_";
        suffix = "_arm64.deb";
      };
      aarch64-darwin = {
        prefix = "Orca-";
        suffix = "-arm64-mac.zip";
      };
    };
    urlTemplate = "https://github.com/stablyai/orca/releases/download/v{version}/{prefix}{version}{suffix}";
  };

  desktopItem = makeDesktopItem {
    name = "orca-ide";
    desktopName = "Orca";
    genericName = "Agentic Development Environment";
    comment = "Next-gen IDE for parallel agentic development";
    exec = "orca-ide %U";
    icon = "orca-ide";
    categories = [ "Development" ];
    # Electron reports WM_CLASS=orca even though the executable is orca-ide,
    # so docks only group the window with this exact value.
    startupWMClass = "orca";
    mimeTypes = [ "x-scheme-handler/orca" ];
  };
in
(stdenvNoCC.mkDerivation {
  pname = "orca";
  inherit (source) version src;

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

  # dlopen()ed at runtime, so not discoverable from DT_NEEDED; list them
  # here to put them on the RUNPATH. libglvnd is the exception and goes on the
  # wrapper's LD_LIBRARY_PATH instead: ANGLE's bundled libEGL.so dlopen()s the
  # native libEGL.so.1, and RUNPATH on that object alone does not survive
  # fixup, so without it Chromium falls back to SwiftShader and the WebGL
  # terminal renderer runs on the CPU.
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

    # Keep the upstream opt/Orca layout so the bundled libs (libffmpeg.so),
    # resources/, and app.asar.unpacked all resolve relative to the binary.
    mkdir -p $out/lib $out/bin $out/share
    cp -a opt/Orca $out/lib/Orca
    cp -a usr/share/icons $out/share/icons

    # chrome-sandbox needs setuid root, which a store path can never have.
    # Electron falls back to user namespaces, as it does for every other
    # prebuilt Electron app here.
    rm -f $out/lib/Orca/chrome-sandbox

    chmod +x $out/lib/Orca/orca-ide $out/lib/Orca/resources/bin/orca-ide

    makeWrapper "$out/lib/Orca/orca-ide" "$out/bin/orca-ide" \
      --suffix PATH : "${
        lib.makeBinPath [
          git
          xclip
          xdg-utils
          xdotool
          xvfb
          xvfb-run
        ]
      }" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}" \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    # CLI launches bypass the GUI wrapper. Wrap the bundled shim itself so
    # `orca open` and Orca's self-installed symlink also inherit native EGL.
    wrapProgram "$out/lib/Orca/resources/bin/orca-ide" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}"

    # The shim re-execs the Electron binary under ELECTRON_RUN_AS_NODE on the
    # CLI entrypoint in app.asar.unpacked. Upstream's deb symlinks it onto PATH
    # from after-install.sh; expose it as `orca`, the name the docs use.
    makeWrapper "$out/lib/Orca/resources/bin/orca-ide" "$out/bin/orca" \
      --suffix PATH : "${
        lib.makeBinPath [
          git
          xclip
          xdg-utils
          xdotool
          xvfb
          xvfb-run
        ]
      }"

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";

    updater = mkUpdater (
      source.updater
      // {
        # /releases/latest skips the -rc.N tags, which upstream marks as
        # prereleases.
        versionSource = {
          type = "github";
          owner = "stablyai";
          repo = "orca";
        };
      }
    );
  };

  meta = with lib; {
    description = "ADE for working with a fleet of parallel coding agents";
    homepage = "https://onorca.dev";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${source.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ andreszb ];
    mainProgram = "orca-ide";
    platforms = source.platforms;
  };
}).overrideAttrs
  (
    lib.optionalAttrs stdenvNoCC.hostPlatform.isDarwin {
      nativeBuildInputs = [ unzip ];
      buildInputs = [ ];
      runtimeDependencies = [ ];
      desktopItems = [ ];
      unpackPhase = null;
      sourceRoot = ".";
      dontFixup = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications $out/bin
        cp -a Orca.app $out/Applications/
        ln -s $out/Applications/Orca.app/Contents/MacOS/Orca $out/bin/orca-ide
        ln -s $out/Applications/Orca.app/Contents/Resources/bin/orca $out/bin/orca
        runHook postInstall
      '';
    }
  )
