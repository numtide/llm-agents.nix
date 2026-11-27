{
  lib,
  flake,
  stdenv,
  platformSource,
  mkUpdater,
  dpkg,
  formatelf,
  makeWrapper,
  vulkan-loader,
  openssl,
  libxkbcommon,
  alsa-lib,
  alsa-plugins,
  pipewire,
  symlinkJoin,
  wayland,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libva,
  fontconfig,
  openblas,
  curl,
  wl-clipboard,
  wtype,
  ffmpeg-headless,
  versionCheckHook,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "x64";
      aarch64-linux = "arm64";
    };
    urlTemplate = "https://github.com/anomalyco/hex/releases/download/v{version}/hex-{version}-linux-{platform}.deb";
  };
  alsaPlugins = symlinkJoin {
    name = "hex-alsa-plugins";
    paths = [
      "${pipewire}/lib/alsa-lib"
      "${alsa-plugins}/lib/alsa-lib"
    ];
  };
in
stdenv.mkDerivation {
  pname = "hex";
  inherit (source) version src;
  nativeBuildInputs = [
    dpkg
    formatelf
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    vulkan-loader
    openssl
    libxkbcommon
    alsa-lib
  ];
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    dpkg-deb -x "$src" .
    mv usr "$out"
    substituteInPlace "$out/lib/systemd/user/hex.service" "$out/share/applications/anomaly.hex.desktop" \
      --replace-fail /usr/bin/hex "$out/bin/hex"
    wrapProgram "$out/bin/hex" \
      --set ALSA_PLUGIN_DIR "${alsaPlugins}" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          wayland
          libx11
          libxcb
          libxcursor
          libxi
          libva
          pipewire
          fontconfig
          openblas
          libxkbcommon
        ]
      }" \
      --prefix PATH : "${
        lib.makeBinPath [
          curl
          wl-clipboard
          wtype
          ffmpeg-headless
        ]
      }"
    runHook postInstall
  '';
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  passthru = {
    category = "Voice & Transcription";
    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "github";
          owner = "anomalyco";
          repo = "hex";
        };
      }
    );
  };
  meta = {
    description = "Local voice dictation for the desktop";
    homepage = "https://github.com/anomalyco/hex";
    changelog = "https://github.com/anomalyco/hex/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    inherit (source) platforms;
    mainProgram = "hex";
    maintainers = [ flake.lib.maintainers.pszponder ];
  };
}
