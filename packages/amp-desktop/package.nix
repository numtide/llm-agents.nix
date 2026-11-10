{
  lib,
  flake,
  platformSource,
  mkUpdater,
  stdenvNoCC,
  formatelf,
  makeWrapper,
  dpkg,

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
  libXcursor,
  libva,
  pciutils,
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
      x86_64-linux = "amd64";
      aarch64-linux = "arm64";
    };
    urlTemplate = "https://static.ampcode.com/linux/{version}/amp-desktop-{version}-{platform}.deb";
  };
in
stdenvNoCC.mkDerivation {
  pname = "amp-desktop";
  inherit (source) version src;

  nativeBuildInputs = [
    dpkg
    formatelf
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

  # dlopen()ed
  runtimeDependencies = [
    libnotify
    libpulseaudio
    libsecret
    libXcursor
    (lib.getLib libva)
    pciutils
    pipewire
    wayland
  ];

  # Also dlopen()ed from the bundled libraries, which runtimeDependencies skips.
  appendRunpaths = map (p: "${lib.getLib p}/lib") [
    libglvnd
    vulkan-loader
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    cp -a opt/amp $out/lib/amp-desktop
    cp -a usr/share/icons usr/share/applications $out/share

    substituteInPlace $out/share/applications/amp-desktop.desktop \
      --replace-fail /opt/amp/amp-desktop amp-desktop

    # needs setuid; Electron falls back to user namespaces
    rm -f $out/lib/amp-desktop/chrome-sandbox

    # The bundled loader does not search /run/opengl-driver for ICDs.
    ln -sf ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $out/lib/amp-desktop/libvulkan.so.1

    # "Open at Login" would pin process.execPath, a store path. The asar
    # header records file offsets, so keep the byte length.
    asar=$out/lib/amp-desktop/resources/app.asar
    if [[ $(grep -aoF 'process.execPath,' "$asar" | wc -l) != 1 ]]; then
      echo "expected exactly one process.execPath in $asar" >&2
      exit 1
    fi
    sed -i 's/process\.execPath,/"amp-desktop",   /' "$asar"

    # glib: gdbus probes for a tray host
    makeWrapper "$out/lib/amp-desktop/amp-desktop" "$out/bin/amp-desktop" \
      --suffix PATH : "${
        lib.makeBinPath [
          glib
          xdg-utils
        ]
      }" \
      --prefix XDG_DATA_DIRS : "$out/share:$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH"

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";

    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "text";
          url = "https://static.ampcode.com/linux/dists/stable/main/binary-amd64/Packages";
          regex = "(?m)^Version: (\\S+)$";
        };
      }
    );
  };

  meta = with lib; {
    description = "Desktop app for Amp, the frontier coding agent";
    homepage = "https://ampcode.com/docs/apps/linux";
    changelog = "https://ampcode.com/chronicle";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ j4n-r ];
    mainProgram = "amp-desktop";
    platforms = source.platforms;
  };
}
