{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  jemalloc,
  openssl,
  onnxruntime,
  libGL,
  libxkbcommon,
  wayland,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "localgpt";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "localgpt-app";
    repo = "localgpt";
    tag = "v${version}";
    hash = "sha256-QTqFgDYQUf2uVZ95IfI89sf9aAEnOIKJVp7oF9rKDAc=";
  };

  cargoHash = "sha256-nMx5V5zLPNpAeQYjChEyywCpBb07U2PIkELjwNvWzj8=";

  # Disable slow LTO and single codegen-unit for faster Nix builds.
  # Use system openssl instead of vendored (which needs perl to build from source).
  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = true' 'lto = false' \
      --replace-fail 'codegen-units = 1' "" \
      --replace-fail 'native-tls-vendored' 'native-tls'
  '';

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    jemalloc
    openssl
    onnxruntime
    # eframe/glow compile-time deps (desktop feature is default)
    libGL
    libxkbcommon
    wayland
    libx11
    libxcursor
    libxi
    libxrandr
  ];

  env = {
    # Use system onnxruntime instead of downloading binaries
    ORT_LIB_LOCATION = "${lib.getLib onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
    JEMALLOC_OVERRIDE = "${lib.getLib jemalloc}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
  };

  # Add runtime library paths for dlopen'd libs (onnxruntime, GL, wayland, xkbcommon)
  postFixup = ''
    patchelf --add-rpath "${
      lib.makeLibraryPath [
        onnxruntime
        libGL
        libxkbcommon
        wayland
      ]
    }" $out/bin/localgpt
  '';

  # Tests require network access and writable directories
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Local AI assistant with persistent markdown memory, autonomous tasks, and semantic search";
    homepage = "https://github.com/localgpt-app/localgpt";
    changelog = "https://github.com/localgpt-app/localgpt/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    # onnxruntime rpath linking is broken on Darwin
    platforms = platforms.linux;
    mainProgram = "localgpt";
  };
}
