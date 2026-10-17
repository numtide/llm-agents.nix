{
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

  # Directly linked (DT_NEEDED); autoPatchelfHook resolves these from
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

  # Provides libudev, which the main binary links directly. The libs-only
  # build avoids pulling the whole systemd closure.
  systemdLibs,

  # Loaded at runtime via dlopen. Nothing lists these in DT_NEEDED, so they go
  # in runtimeDependencies to land on the RUNPATH regardless.
  libglvnd,
  libsecret,
  libnotify,
  libpulseaudio,
  libayatana-appindicator,
  libXcursor,
  pipewire,
  wayland,
  xdg-utils,

  # Needed by the bundled virtiofsd, which backs Cowork's virtual machines.
  libcap_ng,
  libseccomp,

  OVMF,
  virtiofsd,
  runCommandLocal,

  buildFHSEnv,
  mesa,
  vulkan-loader,
  systemdMinimal,

  # Needed for XDG_ICON_DIRS and GSETTINGS_SCHEMAS_PATH.
  adwaita-icon-theme,
  gsettings-desktop-schemas,

  # Command line arguments which are always passed to the application.
  commandLineArgs ? "",
}:

let
  pname = "claude-desktop";

  # update.py refreshes version/urls/hashes from Anthropic's APT index for
  # Linux and from the darwin RELEASES.json feed for macOS.
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) urls hashes;

  platform = stdenvNoCC.hostPlatform.system;

  # The darwin channel is versioned independently of the APT one (it even
  # uses a different numbering scheme), so hashes.json carries per-platform
  # version overrides; platforms without an entry follow the top-level
  # version, which update.py keeps in sync with x86_64-linux.
  version = (versionData.versions or { }).${platform} or versionData.version;

  srcFor =
    system:
    fetchurl {
      url = urls.${system} or (throw "Unsupported system: ${system}");
      hash = hashes.${system} or (throw "Unsupported system: ${system}");
    };

  # x-scheme-handler/claude registers the OAuth sign-in handler.
  # xdg-desktop-portal rejects the app unless the file is named after its app ID.
  desktopItem = makeDesktopItem {
    name = "com.anthropic.Claude";
    desktopName = "Claude";
    genericName = "AI Assistant";
    comment = "Desktop application for Claude.ai";
    exec = "claude-desktop %U";
    icon = "claude-desktop";
    keywords = [
      "AI"
      "Chat"
      "Assistant"
      "Claude"
      "Code"
      "LLM"
    ];
    categories = [
      "Utility"
      "Development"
    ];
    startupNotify = true;
    startupWMClass = "com.anthropic.Claude";
    singleMainWindow = true;
    mimeTypes = [ "x-scheme-handler/claude" ];
    actions = {
      NewChat = {
        name = "New chat";
        exec = "claude-desktop claude://claude.ai/new";
      };
      NewCode = {
        name = "New Claude Code session";
        exec = "claude-desktop claude://code/new";
      };
    };
  };

  # Cowork's VM probes Debian's fixed firmware paths. qemu itself comes from
  # the host PATH; bundling it grows the closure by ~0.8 GiB.
  coworkFirmware =
    let
      dir = if stdenvNoCC.hostPlatform.isAarch64 then "AAVMF" else "OVMF";
    in
    runCommandLocal "claude-desktop-cowork-firmware" { } ''
      mkdir -p $out/share/${dir}
      ln -s ${OVMF.firmware} ${OVMF.variables} $out/share/${dir}/
    '';

  teamId = "Q6L2SF6YDW";

  passthru = {
    category = "AI Coding Agents";
    tests.codesign = mkCodesignCheck {
      name = pname;
      inherit teamId;
      srcs = [ (srcFor "aarch64-darwin") ];
    };
  };

  meta = with lib; {
    description = "Desktop application for Claude.ai";
    homepage = "https://claude.ai";
    # No upstream versioned changelog or release tags exist.
    changelog = "https://claude.ai/download";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ flexiondotorg ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      # The macOS artifact is one universal zip (arm64 + x86_64 slices), but
      # x86_64-darwin is not a supported system in this repo.
      "aarch64-darwin"
    ];
    mainProgram = "claude-desktop";
  };

  unwrapped = stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      meta
      passthru
      ;

    src = srcFor platform;

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
      libcap_ng
      libdrm
      libgbm
      libseccomp
      libX11
      libxcb
      libXcomposite
      libXcursor
      libXdamage
      libXext
      libXfixes
      libXrandr
      libxkbcommon
      nspr
      nss
      pango
      pipewire
      systemdLibs
    ];

    # dlopen()ed at runtime, so autoPatchelfHook cannot discover them from
    # DT_NEEDED; list them here to force them onto every payload's RUNPATH.
    runtimeDependencies = [
      libayatana-appindicator
      libglvnd
      libnotify
      libpulseaudio
      libsecret
      pipewire
      wayland
    ];

    desktopItems = [ desktopItem ];

    unpackPhase = ''
      runHook preUnpack
      ${lib.getExe' bintools "ar"} x $src
      tar xf data.tar.xz
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      # Keep the upstream usr/lib layout so bundled libs (e.g. libffmpeg.so)
      # resolve next to the main binary.
      mkdir -p $out/lib $out/bin $out/share
      cp -a usr/lib/claude-desktop $out/lib/claude-desktop
      cp -a usr/share/icons $out/share/icons
      cp -a usr/share/doc $out/share/doc

      # autoPatchelfHook sets the interpreter and RUNPATHs. The wrapper only adds
      # the app dir (so the bundled GL/Vulkan libs find each other), xdg-utils on
      # PATH, and the icon/schema data dirs.
      makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
        --prefix LD_LIBRARY_PATH : "$out/lib/claude-desktop" \
        --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
        --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
        --add-flags ${lib.escapeShellArg commandLineArgs}

      runHook postInstall
    '';
  };

  # macOS ships as a signed and notarized universal zip containing Claude.app
  # at the root. It is installed as-is: any post-install munging (strip,
  # shebang patching, ...) would invalidate Anthropic's Developer ID signature.
  darwin = stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      meta
      passthru
      ;

    src = srcFor platform;

    nativeBuildInputs = [ unzip ];

    # The default unpack phase would cd into the single top-level Claude.app
    # directory it detects; keep the extraction root as the working directory
    # so the install phase can copy the bundle itself.
    sourceRoot = ".";

    # Preserve the upstream code signature; fixup could modify sealed files.
    dontFixup = true;

    doInstallCheck = true;
    nativeInstallCheckInputs = [ codesignCheckHook ];
    codesignTeamId = teamId;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications $out/bin
      cp -a Claude.app $out/Applications/Claude.app

      # The bundle's own Info.plist registers the claude:// scheme handlers;
      # this symlink just puts the GUI binary on PATH.
      ln -s $out/Applications/Claude.app/Contents/MacOS/Claude $out/bin/claude-desktop

      runHook postInstall
    '';
  };
in
if stdenvNoCC.hostPlatform.isDarwin then
  darwin
else
  # The app downloads and execs generic-linux binaries (claude-code CLI, uv) at
  # runtime, which need an FHS loader path.
  buildFHSEnv {
    inherit pname version meta;
    passthru = passthru // {
      inherit unwrapped;
    };

    targetPkgs = _: [
      unwrapped
      gcc-unwrapped.lib
      # GPU acceleration
      libglvnd
      mesa
      libgbm
      vulkan-loader
      systemdMinimal # /usr/bin/busctl, used to probe for desktop portals
      virtiofsd
      coworkFirmware
    ];

    runScript = "claude-desktop";

    # buildFHSEnv only links a fixed set of host /etc entries, which leaves out
    # /etc/gitconfig, so git in the app's Claude Code sessions lost the system
    # identity and signing config.
    extraBwrapArgs = [ "--ro-bind-try /etc/gitconfig /etc/gitconfig" ];

    extraInstallCommands = ''
      ln -s ${unwrapped}/share $out/share
    '';
  }
