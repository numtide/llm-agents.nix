{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  installShellFiles,
  makeWrapper,
  rustPlatform,
  pkg-config,
  openssl,
  bubblewrap,
  libcap,
  versionCheckHook,
  mkRustyV8Archive,
  versionData ? builtins.fromJSON (builtins.readFile ./hashes.json),
  version ? versionData.version,
  hash ? versionData.hash,
  src ? fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    tag = "rust-v${version}";
    inherit hash;
  },
  sourceRoot ? "source/codex-rs",
  cargoVendor ? {
    cargoHash = versionData.cargoHash;
  },
  preBuild ? ''
    # Upstream's low codegen-units (4 since 0.140.0) makes late-stage rustc
    # hold large IR modules, peaking at ~12 GiB and OOMing our 16 GiB aarch64
    # builder. Raise to 16 to bound memory; __TEXT still stays below the
    # 128 MiB ARM64 branch range the Mach-O linker hit on aarch64-darwin (#4417).
    substituteInPlace Cargo.toml \
      --replace-fail 'codegen-units = 4' 'codegen-units = 16'
  '',
  doInstallCheck ? true,
  librusty_v8 ? mkRustyV8Archive versionData.librusty_v8,
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

let
  # codex-realtime-webrtc pulls in livekit's webrtc-sys on macOS, whose
  # build.rs would download a ~300MB prebuilt libwebrtc archive at build
  # time. Prefetch it as a fixed-output derivation and point the crate at
  # it via LK_CUSTOM_WEBRTC so the build stays sandboxed.
  livekitWebrtcTriple =
    {
      x86_64-darwin = "mac-x64";
      aarch64-darwin = "mac-arm64";
    }
    .${stdenv.hostPlatform.system} or null;
  livekitWebrtc =
    if livekitWebrtcTriple == null then
      null
    else
      fetchzip {
        name = "livekit-webrtc-${versionData.livekit_webrtc.tag}-${livekitWebrtcTriple}";
        url = "https://github.com/livekit/rust-sdks/releases/download/${versionData.livekit_webrtc.tag}/webrtc-${livekitWebrtcTriple}-release.zip";
        hash = versionData.livekit_webrtc.hashes.${stdenv.hostPlatform.system};
        meta.sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
in
rustPlatform.buildRustPackage (
  {
    pname = "codex";
    inherit version src sourceRoot;

    cargoBuildFlags = [
      "--package"
      "codex-cli"
    ];

    nativeBuildInputs = [
      installShellFiles
      makeWrapper
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      # Unable to find libclang: "couldn't find any valid shared libraries matching: ['libclang.dylib']
      rustPlatform.bindgenHook
    ];

    buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isLinux [ libcap ];

    env = {
      RUSTY_V8_ARCHIVE = librusty_v8;
      # Cap concurrent rustc jobs to keep peak RSS bounded with ThinLTO on the
      # 16 GiB aarch64 builder.
      CARGO_BUILD_JOBS = "2";
      # Drop debuginfo from the shipped binary; combined with ThinLTO this
      # keeps the codex __TEXT segment well below the 128 MiB ARM64 branch
      # limit on aarch64-darwin.
      CARGO_PROFILE_RELEASE_DEBUG = "false";
      CARGO_PROFILE_RELEASE_STRIP = "symbols";
    }
    // lib.optionalAttrs (livekitWebrtc != null) {
      LK_CUSTOM_WEBRTC = livekitWebrtc;
    };

    inherit preBuild;

    postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      mkdir -p $out/codex-resources
      ln -s ${lib.getExe bubblewrap} $out/codex-resources/bwrap

      wrapProgram $out/bin/codex \
        --prefix PATH : ${lib.makeBinPath [ bubblewrap ]}
    '';

    doCheck = false;

    postInstall = lib.optionalString installShellCompletions ''
      installShellCompletion --cmd codex \
        --bash <($out/bin/codex completion bash) \
        --fish <($out/bin/codex completion fish) \
        --zsh <($out/bin/codex completion zsh)
    '';

    inherit doInstallCheck;
    nativeInstallCheckInputs = [ versionCheckHook ];

    passthru = {
      category = "AI Coding Agents";
      inherit mkRustyV8Archive;
      inherit librusty_v8;
    };

    meta = {
      description = "OpenAI Codex CLI - a coding agent that runs locally on your computer";
      homepage = "https://github.com/openai/codex";
      changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode # librusty_v8
      ];
      license = lib.licenses.asl20;
      mainProgram = "codex";
      platforms = lib.platforms.unix;
    };
  }
  // cargoVendor
)
