{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  makeWrapper,
  rustPlatform,
  pkg-config,
  openssl,
  bubblewrap,
  libcap,
  versionCheckHook,
  callPackage,
  mkRustyV8Archive ? callPackage ../../corepkgs/lib/rusty-v8.nix { },
  versionData ? builtins.fromJSON (builtins.readFile ./hashes.json),
  version ? versionData.version,
  hash ? versionData.hash,
  # Named srcOverride because a `src` argument would be autofilled by
  # callPackage from the throwing `pkgs.src` alias.
  srcOverride ? null,
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
  actualSrc =
    if srcOverride != null then
      srcOverride
    else
      fetchFromGitHub {
        owner = "openai";
        repo = "codex";
        tag = "rust-v${version}";
        inherit hash;
      };

in
rustPlatform.buildRustPackage (
  {
    pname = "codex";
    inherit version sourceRoot;
    src = actualSrc;

    cargoBuildFlags = [
      "--package"
      "codex-cli"
      "--package"
      "codex-code-mode-host"
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
    }
    // lib.optionalAttrs (librusty_v8 ? srcBinding) {
      # rusty_v8 >= 150 include!s this instead of running bindgen.
      RUSTY_V8_SRC_BINDING_PATH = librusty_v8.srcBinding;
    }
    // {
      # Cap concurrent rustc jobs to keep peak RSS bounded with ThinLTO on the
      # 16 GiB aarch64 builder.
      CARGO_BUILD_JOBS = "2";
      # Drop debuginfo from the shipped binary; combined with ThinLTO this
      # keeps the codex __TEXT segment well below the 128 MiB ARM64 branch
      # limit on aarch64-darwin.
      CARGO_PROFILE_RELEASE_DEBUG = "false";
      CARGO_PROFILE_RELEASE_STRIP = "symbols";
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
