{
  lib,
  flake,
  stdenvNoCC,
  fetchurl,
  dpkg,
  unzip,
  formatelf,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  wrapGAppsHook3,
  codesignCheckHook,
  mkCodesignCheck,
  versionCheckHomeHook,
  adwaita-icon-theme,
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
  gsettings-desktop-schemas,
  gtk3,
  libayatana-appindicator,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  python3,
  systemdLibs,
  wayland,
  xdg-utils,
  commandLineArgs ? "",
}:

let
  pname = "workbuddy";
  versionData = lib.importJSON ./hashes.json;
  platform = stdenvNoCC.hostPlatform.system;
  version = versionData.versions.${platform};
  arch = if stdenvNoCC.hostPlatform.isAarch64 then "arm64" else "x64";

  srcFor =
    system:
    fetchurl {
      url = versionData.urls.${system};
      hash = versionData.hashes.${system};
    };

  # Keep the signed bundle in its own derivation, without fixup. The archive
  # also includes unsigned build intermediates and third-party signatures, so
  # check the application's Developer ID rather than requiring every bundled
  # Mach-O (including .o and debug files) to have the same signer.
  teamId = "FN2V63AD2J";
  darwinBundle = stdenvNoCC.mkDerivation {
    pname = "${pname}-darwin-bundle";
    version = versionData.versions.aarch64-darwin;
    src = srcFor "aarch64-darwin";
    nativeBuildInputs = [ unzip ];
    sourceRoot = ".";
    dontFixup = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications $out/bin
      cp -a 'WorkBuddy AI.app' $out/Applications/
      ln -s '../Applications/WorkBuddy AI.app/Contents/MacOS/Electron' $out/bin/workbuddy
      runHook postInstall
    '';
    doInstallCheck = true;
    nativeInstallCheckInputs = [ python3 ];
    installCheckPhase = ''
      runHook preInstallCheck
      python3 - "$out/Applications/WorkBuddy AI.app/Contents/Info.plist" ${lib.escapeShellArg versionData.versions.aarch64-darwin} <<'PY'
      import plistlib
      import sys

      with open(sys.argv[1], "rb") as stream:
          info = plistlib.load(stream)
      assert info["CFBundleIdentifier"] == "com.workbuddy.workbuddy-ai"
      assert info["CFBundleShortVersionString"] == ".".join(sys.argv[2].split(".")[:3])
      PY
      runHook postInstallCheck
    '';
  };
  darwinExecutable = "${darwinBundle}/bin/workbuddy";

  passthru = {
    category = "AI Assistants";
    tests.codesign = mkCodesignCheck {
      name = pname;
      inherit teamId;
      srcs = [ darwinExecutable ];
    };
  };

  meta = {
    description = "Desktop AI assistant for working with local files and automating tasks";
    homepage = "https://www.workbuddy.ai/";
    changelog =
      if stdenvNoCC.hostPlatform.isDarwin then
        "https://www.workbuddy.ai/docs/workbuddy/Changelog#_${
          lib.replaceStrings [ "." ] [ "-" ] (lib.versions.majorMinorPatch version)
        }"
      else
        "https://www.workbuddy.cn/docs/workbuddy/Changelog-${lib.versions.majorMinorPatch version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.Ign1x ];
    mainProgram = "workbuddy";
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
      meta
      passthru
      ;
    src = srcFor platform;

    nativeBuildInputs = [
      dpkg
      formatelf
      makeWrapper
      copyDesktopItems
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
    # Chromium also loads these libraries through dlopen rather than DT_NEEDED.
    runtimeDependencies = [
      libayatana-appindicator
      libnotify
      libpulseaudio
      libsecret
      libXcursor
      pipewire
      wayland
    ];
    # ANGLE and native addons dlopen OpenGL from shared objects, whose
    # RUNPATHs do not receive runtimeDependencies (only executables do).
    appendRunpaths = [ (lib.makeLibraryPath [ libglvnd ]) ];

    # The payload includes native addons and standalone agent executables.
    dontStrip = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/bin $out/share
      cp -a opt/WorkBuddy $out/lib/workbuddy
      cp -a usr/share/icons $out/share/

      # Koffi ships prebuilds for other OSes, including FreeBSD and musl.
      # Retain only the glibc prebuild for this host before ELF fixup.
      find $out/lib/workbuddy/resources/app.asar.unpacked/node_modules/koffi/build/koffi \
        -mindepth 1 -maxdepth 1 ! -name linux_${arch} -exec rm -rf {} +

      # auto-formatelf resolves dependencies by basename. Upstream embeds a
      # relative path in this DT_NEEDED entry; the bundled library is present.
      formatelf --replace-needed \
        '$ORIGIN/../lib/libpython3.13.so.1.0' libpython3.13.so.1.0 \
        $out/lib/workbuddy/resources/runtime/python/lib/libpython3.so

      makeWrapper $out/lib/workbuddy/workbuddy $out/bin/workbuddy \
        --prefix LD_LIBRARY_PATH : "$out/lib/workbuddy" \
        --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
        --add-flags ${lib.escapeShellArg commandLineArgs}

      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "workbuddy";
        desktopName = "WorkBuddy";
        comment = "Desktop AI assistant";
        exec = "workbuddy %U";
        icon = "workbuddy";
        startupWMClass = "workbuddy";
        categories = [
          "Utility"
          "Development"
        ];
        mimeTypes = [ "x-scheme-handler/workbuddy" ];
      })
    ];

    # A GUI --version invocation starts the app. Check the packaged metadata
    # and load native modules with the bundled Electron instead.
    doInstallCheck = true;
    nativeInstallCheckInputs = [ versionCheckHomeHook ];
    installCheckPhase = ''
      runHook preInstallCheck

      ELECTRON_RUN_AS_NODE=1 $out/lib/workbuddy/workbuddy \
        ${./runtime-smoke.cjs} $out/lib/workbuddy ${lib.escapeShellArg version}
      $out/lib/workbuddy/resources/runtime/node/bin/node \
        $out/lib/workbuddy/resources/app.asar.unpacked/cli/bin/codebuddy --version
      $out/lib/workbuddy/resources/runtime/python/bin/python3 \
        -c 'import ctypes, sqlite3, ssl; print("Bundled Python modules load successfully")'
      test -f $out/share/applications/workbuddy.desktop
      test -f $out/share/icons/hicolor/256x256/apps/workbuddy.png

      runHook postInstallCheck
    '';
  };

  darwin = stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      meta
      passthru
      ;
    src = srcFor platform;
    dontUnpack = true;
    dontFixup = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications $out/bin
      ln -s '${darwinBundle}/Applications/WorkBuddy AI.app' "$out/Applications/WorkBuddy AI.app"
      ln -s ${darwinExecutable} $out/bin/workbuddy
      runHook postInstall
    '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [ codesignCheckHook ];
    codesignTeamId = teamId;
    codesignSources = [ darwinExecutable ];
    installCheckPhase = ''
      runHook preInstallCheck
      test -x $out/bin/workbuddy
      test -f "$out/Applications/WorkBuddy AI.app/Contents/Resources/app.asar"
      runHook postInstallCheck
    '';
  };
in
if stdenvNoCC.hostPlatform.isDarwin then darwin else linux
