{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_22,
  electron_43,
  ripgrep,
  sqlite-vec,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  zip,
  pkg-config,
  python3,
  formatelf,
  wayland-scanner,
  wayland,
  libxkbcommon,
  json_c,
  libjpeg_turbo,
  libpng,
  mkUpdater,

  adwaita-icon-theme,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  flac,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libdrm,
  libffi,
  libgbm,
  libglvnd,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libnotify,
  libsecret,
  libxshmfence,
  libxml2,
  libxslt,
  nspr,
  nss,
  pango,
  libpulseaudio,
  pipewire,
  systemdLibs,
  xdg-utils,
  git,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash pnpmDepsHash;

  pname = "cindy";
  electron = electron_43;
  pnpm = pnpm_10;
  arch = if stdenv.hostPlatform.isx86_64 then "x64" else "arm64";

  src = fetchFromGitHub {
    owner = "makecindy";
    repo = "cindy";
    tag = "v${version}";
    inherit hash;
  };

  libraries = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    flac
    glib
    gtk3
    libdrm
    libffi
    libgbm
    libX11
    libxcb
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxkbcommon
    libxshmfence
    libxml2
    libxslt
    libjpeg_turbo
    libpng
    json_c
    nspr
    nss
    pango
    libpulseaudio
    systemdLibs
    stdenv.cc.cc.lib
  ];

  # dlopen()ed
  runtimeDependencies = [
    libglvnd
    libnotify
    libsecret
    libXcursor
    pipewire
    wayland
  ];

  desktopItem = makeDesktopItem {
    name = "cindy";
    desktopName = "Cindy";
    genericName = "AI Assistant";
    comment = "Open-source AI agent desktop client";
    exec = "cindy %U";
    icon = "cindy";
    categories = [ "Development" ];
    mimeTypes = [
      "x-scheme-handler/cindy"
      "x-scheme-handler/xdt-maker"
    ];
    startupNotify = true;
    startupWMClass = "Cindy";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit
      pname
      version
      src
      pnpm
      ;
    fetcherVersion = 3;
    hash = pnpmDepsHash;
  };

in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    pnpmDeps
    ;

  nativeBuildInputs = [
    nodejs_22
    pnpm
    pnpmConfigHook
    makeWrapper
    copyDesktopItems
    zip
    pkg-config
    python3
    formatelf
    wayland-scanner
  ];

  buildInputs = libraries ++ runtimeDependencies;

  dontStrip = true;

  env = {
    APP_VERSION = version;
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    npm_config_build_from_source = "true";
  };

  postPatch = ''
    sed -i '/"packageManager":/d' package.json
    sed -i '/onlyModules: modules,/a\    buildFromSource: true,' \
      apps/desktop/forge.config.ts
    sed -i '/packagerConfig: {/a\    electronZipDir: process.env.CINDY_ELECTRON_ZIP_DIR,' \
      apps/desktop/forge.config.ts
    sed -i 's/"version": "[^"]*"/"version": "${ripgrep.version}"/' \
      tools/ripgrep/latest.json

    # also overrides consent stored by other builds sharing the profile
    substituteInPlace apps/desktop/src/main/analytics-settings-store.ts \
      --replace-fail \
        'function isReportingBuild(): boolean {' \
        'function isReportingBuild(): boolean {
      if (process.env.CINDY_DISABLE_TELEMETRY === "1") return false;' \
      --replace-fail 'analyticsEnabled: true,' 'analyticsEnabled: false,'

    install -Dm644 ${sqlite-vec}/lib/vec0.so \
      apps/desktop/native/sqlite-vec/linux-${arch}/vec0.so
  '';

  preBuild = ''
    export HOME=$TMPDIR

    upstreamElectron=$(node -p "require('./apps/desktop/package.json').devDependencies.electron")
    if (( ''${upstreamElectron%%.*} > ${lib.versions.major electron.version} )); then
      echo "error: upstream expects Electron $upstreamElectron, nixpkgs has ${electron.version}" >&2
      exit 1
    fi

    sed -i 's/"electron": "[^"]*"/"electron": "${electron.version}"/' \
      apps/desktop/package.json
    sed -i '0,/"version": "[^"]*"/s//"version": "${electron.version}"/' \
      node_modules/electron/package.json

    dist=node_modules/electron/dist
    mkdir -p $dist
    cp -R ${electron}/libexec/electron/. $dist/
    chmod -R u+w $dist
    echo electron > node_modules/electron/path.txt
    echo ${electron.version} > $dist/version
    export CINDY_ELECTRON_ZIP_DIR=$TMPDIR/electron-zips
    mkdir -p $CINDY_ELECTRON_ZIP_DIR
    (cd $dist && zip -X -qr $CINDY_ELECTRON_ZIP_DIR/electron-v${electron.version}-linux-${arch}.zip .)
    export npm_config_nodedir=${electron.headers}

    install -Dm755 ${ripgrep}/bin/rg apps/ripgrep-bin/linux-${arch}/rg
    echo ${ripgrep.version} > apps/ripgrep-bin/linux-${arch}/.version
  '';

  buildPhase = ''
    runHook preBuild
    pnpm --filter desktop package
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -R apps/desktop/out/Cindy-linux-${arch} $out/lib/cindy

    # node-gyp build leftovers
    find $out/lib/cindy/resources/app.asar.unpacked/node_modules \
      -type f -path '*/build/*' ! -name '*.node' ! -name spawn-helper -delete
    find $out/lib/cindy/resources/app.asar.unpacked/node_modules -type d -empty -delete
    rm -f $out/lib/cindy/resources/app.asar.unpacked/node_modules/better-sqlite3/build/Release/test_extension.node

    install -Dm644 apps/desktop/resources/icon.png $out/share/icons/hicolor/512x512/apps/cindy.png
    makeWrapper $out/lib/cindy/Cindy $out/bin/cindy \
      --chdir $out/lib/cindy \
      --set CINDY_DISABLE_TELEMETRY 1 \
      --prefix LD_LIBRARY_PATH : "$out/lib/cindy:${lib.makeLibraryPath runtimeDependencies}" \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          xdg-utils
        ]
      } \
      --prefix XDG_DATA_DIRS : "$out/share:${adwaita-icon-theme}/share:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}" \
      --add-flags --no-sandbox
    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

  passthru = {
    category = "AI Assistants";
    updater = mkUpdater {
      kind = "github-source";
      purl = "pkg:github/makecindy/cindy";
      depHashKey = "pnpmDepsHash";
    };
  };

  meta = with lib; {
    description = "Open-source AI agent desktop client";
    homepage = "https://cindy.app";
    changelog = "https://github.com/makecindy/cindy/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ rucadi ];
    mainProgram = "cindy";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
