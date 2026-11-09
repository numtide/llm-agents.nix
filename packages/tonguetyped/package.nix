{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  makeWrapper,
  pkg-config,
  shaderc,
  alsa-lib,
  onnxruntime,
  sqlite,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,
  openssl,
  xdotool,
  libcanberra-gtk3,
  wtype,
  dotool,
  wl-clipboard,
  xclip,
  wayland,
  libxkbcommon,
  dbus,
  versionCheckHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "tonguetyped";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "cheerfulScumbag";
    repo = "tonguetyped";
    tag = "v${version}";
    hash = "sha256-s+5RMmpFA22L5o9kCqQGvlPSwemL1Rupd6+DHHVqw8c=";
  };

  cargoHash = "sha256-MZ0fdBuT0nUhkKgGdud1Jy46YG1S9VhhI1rU/peWUiQ=";

  nativeBuildInputs = [
    cmake
    makeWrapper
    pkg-config
    rustPlatform.bindgenHook
    shaderc
  ];

  buildInputs = [
    alsa-lib
    onnxruntime
    sqlite
    spirv-headers
    vulkan-headers
    vulkan-loader
    openssl
    xdotool
    wayland
    libxkbcommon
  ];

  buildFeatures = [ "gpu-vulkan" ];

  env = {
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    ORT_LIB_LOCATION = "${onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
  };

  nativeCheckInputs = [ dbus ];

  # pty_ tests need a pty, which the sandbox lacks
  cargoTestFlags = [
    "--"
    "--skip"
    "pty_"
  ];

  postInstall = ''
    install -Dm644 data/io.github.cheerfulScumbag.tonguetyped.desktop \
      $out/share/applications/io.github.cheerfulScumbag.tonguetyped.desktop
    install -Dm644 data/icons/hicolor/scalable/apps/io.github.cheerfulScumbag.tonguetyped.svg \
      $out/share/icons/hicolor/scalable/apps/io.github.cheerfulScumbag.tonguetyped.svg
  '';

  postFixup = ''
    wrapProgram $out/bin/tonguetyped \
      --prefix PATH : ${
        lib.makeBinPath [
          libcanberra-gtk3
          wtype
          dotool
          wl-clipboard
          xclip
        ]
      }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Voice & Transcription";

  meta = {
    description = "Local Linux dictation controlled from the terminal or a desktop-wide keyboard shortcut";
    homepage = "https://github.com/cheerfulScumbag/tonguetyped";
    changelog = "https://github.com/cheerfulScumbag/tonguetyped/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ cheerfulScumbag ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "tonguetyped";
  };
}
