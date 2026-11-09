# Packages the upstream "default" variant (CPU, Whisper backend). The other
# variants from upstream's flake (Vulkan/ROCm/ONNX/CUDA) are GPU-specific and
# pull large unfree/accelerator stacks; this ships the portable CPU build.
# Reference: https://github.com/peteonrails/voxtype/blob/v0.7.5/flake.nix
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  clang,
  llvmPackages,
  git,
  makeWrapper,
  alsa-lib,
  oniguruma,
  openssl,
  sqlite,
  # Runtime tools wrapped onto PATH (typing/clipboard/notify backends).
  wtype,
  dotool,
  wl-clipboard,
  ydotool,
  xdotool,
  xclip,
  libnotify,
  pciutils,
}:

rustPlatform.buildRustPackage rec {
  pname = "voxtype";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "peteonrails";
    repo = "voxtype";
    tag = "v${version}";
    hash = "sha256-7Djbq7nUIqL3afCEYKnPWtRnx4jXBvhY4iA1m/4w8Ak=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    # The (optional, unused here) openvino-sys git dependency drags in the
    # OpenVINO submodules. ittapi has a `c-library -> ../../` symlink in there
    # that sends the vendoring copy into an endless recursion. The crate only
    # packages the C headers, so thirdparty is safe to drop.
    postBuild = ''
      rm -r $out/git/*/crates/openvino-sys/upstream/thirdparty
    '';
    hash = "sha256-7MheYBpLNBRLl0kESOQ/Kzfdz6ye/iZrPvxLiMUZPfg=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    clang
    git # whisper.cpp cmake invokes git
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    oniguruma
    openssl
    sqlite
  ];

  env = {
    # whisper-rs runs bindgen against whisper.cpp headers.
    LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    RUSTONIG_SYSTEM_LIBONIG = "1";
  };

  preBuild = ''
    export CMAKE_BUILD_PARALLEL_LEVEL=$NIX_BUILD_CORES
  '';

  # Audio/voice tests need hardware and downloaded models.
  doCheck = false;

  postInstall = ''
    install -Dm644 packaging/completions/voxtype.bash \
      $out/share/bash-completion/completions/voxtype
    install -Dm644 packaging/completions/voxtype.zsh \
      $out/share/zsh/site-functions/_voxtype
    install -Dm644 packaging/completions/voxtype.fish \
      $out/share/fish/vendor_completions.d/voxtype.fish

    install -Dm644 config/default.toml \
      $out/share/voxtype/default-config.toml

    wrapProgram $out/bin/voxtype \
      --prefix PATH : ${
        lib.makeBinPath [
          wtype
          dotool
          wl-clipboard
          ydotool
          xdotool
          xclip
          libnotify
          pciutils
        ]
      }
  '';

  passthru.category = "Voice & Transcription";

  meta = {
    description = "Push-to-talk voice-to-text for Wayland";
    homepage = "https://voxtype.io";
    changelog = "https://github.com/peteonrails/voxtype/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ zimbatm ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "voxtype";
  };
}
