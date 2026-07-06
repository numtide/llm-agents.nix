{
  fetchurl,
  lib,
  makeWrapper,
  patchelf,
  stdenvNoCC,
  bintools,
  copyDesktopItems,
  makeDesktopItem,

  # Linked dynamic libraries.
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
  libglvnd,
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
  pipewire,
  wayland,

  # Provides libudev, which the main binary links directly. The libs-only
  # build avoids pulling the whole systemd closure.
  systemdLibs,

  # Loaded at runtime via dlopen.
  libsecret,
  libnotify,
  libpulseaudio,
  libayatana-appindicator,
  libXcursor,
  xdg-utils,

  # Needed by the bundled virtiofsd, which backs Cowork's virtual machines.
  libcap_ng,
  libseccomp,

  # Needed for XDG_ICON_DIRS and GSETTINGS_SCHEMAS_PATH.
  adwaita-icon-theme,
  gsettings-desktop-schemas,

  # Command line arguments which are always passed to the application.
  commandLineArgs ? "",
}:

let
  pname = "claude-desktop";

  # update.py refreshes version/urls/hashes from Anthropic's APT index.
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version urls hashes;

  platform = stdenvNoCC.hostPlatform.system;

  deps = [
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
    gtk3
    libayatana-appindicator
    libcap_ng
    libdrm
    libglvnd
    libgbm
    libnotify
    libpulseaudio
    libsecret
    libseccomp
    libX11
    libxcb
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libxkbcommon
    libXrandr
    nspr
    nss
    pango
    pipewire
    systemdLibs
    wayland
  ];

  # x-scheme-handler/claude registers the OAuth sign-in handler.
  desktopItem = makeDesktopItem {
    name = "claude-desktop";
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
    startupWMClass = "claude-desktop";
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

  passthru = {
    category = "AI Coding Agents";
  };

  meta = with lib; {
    description = "Desktop application for Claude.ai";
    homepage = "https://claude.ai";
    # No upstream versioned changelog or release tags exist.
    changelog = "https://claude.ai/download";
    license = licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ flexiondotorg ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "claude-desktop";
  };
in
stdenvNoCC.mkDerivation {
  inherit
    pname
    version
    meta
    passthru
    ;

  src = fetchurl {
    url = urls.${platform} or (throw "Unsupported system: ${platform}");
    hash = hashes.${platform} or (throw "Unsupported system: ${platform}");
  };

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
    patchelf
  ];

  buildInputs = [
    adwaita-icon-theme
    glib
    gsettings-desktop-schemas
    gtk3
  ];

  desktopItems = [ desktopItem ];

  unpackPhase = ''
    runHook preUnpack
    ${lib.getExe' bintools "ar"} x $src
    tar xf data.tar.xz
    runHook postUnpack
  '';

  rpath = lib.makeLibraryPath deps;

  installPhase = ''
    runHook preInstall

    # Keep the upstream usr/lib layout so bundled libs (e.g. libffmpeg.so)
    # resolve next to the main binary.
    mkdir -p $out/lib $out/bin $out/share
    cp -a usr/lib/claude-desktop $out/lib/claude-desktop
    cp -a usr/share/icons $out/share/icons
    cp -a usr/share/doc $out/share/doc

    # Include the app dir so ANGLE and the bundled GL/Vulkan libs find each
    # other and the system libGL.
    app_rpath="$rpath:$out/lib/claude-desktop"

    # Patch every dynamic ELF in the app tree; tolerate failures on the
    # statically linked cowork-linux-helper and the smol-bin.x64.img image.
    while IFS= read -r -d "" elf; do
      patchelf --set-interpreter ${bintools.dynamicLinker} "$elf" 2>/dev/null || true
      patchelf --set-rpath "$app_rpath" "$elf" 2>/dev/null || true
    done < <(find $out/lib/claude-desktop -type f \( -name "*.so" -o -name "*.so.*" -o -name "*.node" -o -executable \) -print0)

    makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
      --prefix LD_LIBRARY_PATH : "$app_rpath" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}

    runHook postInstall
  '';
}
