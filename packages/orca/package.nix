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
  gobject-introspection,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
  python3,
  versionCheckHook,
  versionCheckHomeHook,
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
  coreutils,
  openssh,
  which,
  wl-clipboard,
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
  computerUsePython = python3.withPackages (ps: [ ps.pygobject3 ]);
  teamId = "6CX3WHS9HZ";
  runtimeTools = [
    coreutils
    git
    openssh
    python3
    which
    wl-clipboard
    xclip
    xdg-utils
    xdotool
    xvfb
    xvfb-run
  ];
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
    mimeTypes = [
      "text/markdown"
      "text/csv"
      "text/tab-separated-values"
      "x-scheme-handler/orca"
    ];
  };
in
(stdenvNoCC.mkDerivation {
  pname = "orca";
  inherit (source) version src;

  nativeBuildInputs = [
    formatelf
    copyDesktopItems
    makeWrapper
    gobject-introspection
    wrapGAppsHook3
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
    # The Wayland clipboard helper dlopens GTK for its Xwayland fallback.
    gtk3
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

    mkdir -p "$out/libexec"
    cat > "$out/libexec/orca-computer-use.py" <<EOF
    import os
    import sys
    os.execv("$out/libexec/orca-computer-use-python", ["$out/libexec/orca-computer-use-python", *sys.argv[1:]])
    EOF

    runHook postInstall
  '';

  dontWrapGApps = true;
  # orcad-template/targets holds per-platform daemon builds that Orca uploads to
  # remote hosts and verifies by sha256, so they must stay unpatched and unstripped.
  dontStrip = true;
  dontAutoPatchelf = true;
  postFixup = ''
    autoPatchelf \
      $(find "$out/lib/Orca" -mindepth 1 -maxdepth 1 ! -name resources) \
      $(find "$out/lib/Orca/resources" -mindepth 1 -maxdepth 1 ! -name orcad-template)

    makeWrapper "${lib.getExe computerUsePython}" "$out/libexec/orca-computer-use-python" \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "$out/lib/Orca/resources/computer-use-linux/runtime.py"

    # The provider override also reaches local daemon copies, without changing
    # their remote-deployment hashes or the Python used by coding agents.
    launcherArgs=(
      "''${gappsWrapperArgs[@]}"
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS"
      --set-default ORCA_COMPUTER_DESKTOP_SCRIPT_PROVIDER_PATH "$out/libexec/orca-computer-use.py"
      --suffix PATH : "${lib.makeBinPath runtimeTools}"
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}"
    )
    makeWrapper "$out/lib/Orca/orca-ide" "$out/bin/orca-ide" "''${launcherArgs[@]}"
    wrapProgram "$out/lib/Orca/resources/bin/orca-ide" "''${launcherArgs[@]}"
    ln -s "$out/lib/Orca/resources/bin/orca-ide" "$out/bin/orca"
  '';

  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/orca";
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  postInstallCheck = ''
    makeWrapper "${lib.getExe computerUsePython}" "$TMPDIR/check-computer-use-python" \
      "''${gappsWrapperArgs[@]}"
    "$TMPDIR/check-computer-use-python" -c '
    import gi
    gi.require_version("Atspi", "2.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import Atspi, Gdk, GdkPixbuf
    '
  '';

  passthru = {
    category = "AI Coding Agents";
    tests.codesign = mkCodesignCheck {
      name = "orca";
      inherit teamId;
      srcs = source.darwinSrcs;
    };

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
      nativeBuildInputs = [
        unzip
        makeWrapper
      ];
      buildInputs = [ ];
      runtimeDependencies = [ ];
      desktopItems = [ ];
      unpackPhase = null;
      sourceRoot = ".";
      dontFixup = true;
      postFixup = "";
      nativeInstallCheckInputs = [
        versionCheckHook
        versionCheckHomeHook
        codesignCheckHook
      ];
      codesignTeamId = teamId;
      postInstallCheck = "";

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications $out/bin
        cp -a Orca.app $out/Applications/
        makeWrapper $out/Applications/Orca.app/Contents/MacOS/Orca $out/bin/orca-ide
        ln -s $out/Applications/Orca.app/Contents/Resources/bin/orca $out/bin/orca
        runHook postInstall
      '';
    }
  )
