# Built from source, adapted from upstream's own flake:
#   https://github.com/cheerfulScumbag/tonguetyped/blob/v0.2.2/flake.nix
#
# Only the default `gpu-vulkan` variant is packaged. The CUDA/ROCm variants
# need unfree accelerator stacks and are out of scope here.
{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  desktop-file-utils,
  libclang,
  makeWrapper,
  pkg-config,
  shaderc,
  alsa-lib,
  onnxruntime,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,
  openssl,
  xdotool,
  libcanberra-gtk3,
  glibc,
  dbus,
}:

rustPlatform.buildRustPackage rec {
  pname = "tonguetyped";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "cheerfulScumbag";
    repo = "tonguetyped";
    tag = "v${version}";
    hash = "sha256-6IvPDbMJyt+ZGkY8IJO56ac8wkRdNnu0YASK67ybFOA=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    hash = "sha256-79+uC0EvrQ7ndGCngLzCI29Wp9taDZQPWcLZiuNC8HY=";
  };

  nativeBuildInputs = [
    cmake
    desktop-file-utils
    libclang
    makeWrapper
    pkg-config
    shaderc
  ];

  buildInputs = [
    alsa-lib
    onnxruntime
    spirv-headers
    vulkan-headers
    vulkan-loader
    openssl
    xdotool
  ];

  buildFeatures = [ "gpu-vulkan" ];

  env = {
    LIBCLANG_PATH = "${lib.getLib libclang}/lib";
    BINDGEN_EXTRA_CLANG_ARGS = "-I${lib.getDev glibc}/include";
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    ORT_LIB_LOCATION = "${onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
  };

  doCheck = true;

  # `tests/media_pause.rs` starts a private dbus-daemon; the `pty_*` tests in
  # `tests/tui_dashboard.rs` need a real pty the sandbox checkPhase lacks.
  nativeCheckInputs = [ dbus ];

  cargoTestFlags = [
    "--"
    "--skip"
    "pty_"
  ];

  postInstall = ''
    install -Dm644 data/tonguetyped.desktop \
      $out/share/applications/io.github.cheerfulScumbag.tonguetyped.desktop
  '';

  postFixup = ''
    wrapProgram $out/bin/tonguetyped \
      --prefix PATH : ${lib.makeBinPath [ libcanberra-gtk3 ]}
  '';

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
