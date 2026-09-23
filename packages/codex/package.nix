{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  makeWrapper,
  rustPlatform,
  pkg-config,
  lld,
  openssl,
  bubblewrap,
  libcap,
  versionCheckHook,
  callPackage,
  mkRustyV8Archive ? callPackage ../../lib/rusty-v8.nix { },
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
    # Upstream's ThinLTO + codegen-units=4 make late-stage rustc peak at
    # ~12 GiB and the whole build crawl; fall back to cargo defaults like
    # nixpkgs does.
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "thin"' "" \
      --replace-fail 'codegen-units = 4' ""
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
    // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
      # nixpkgs' ld64 fails to insert ARM64 branch thunks for this binary
      # (`b(l) ARM64 branch out of range`, #4417); lld handles it.
      NIX_CFLAGS_LINK = "-fuse-ld=${lib.getExe' lld "ld64.lld"}";
    };

    # The future returned by `connectors::list_connectors` nests deeply
    # enough that computing its layout exceeds rustc's default query depth
    # limit of 128 ("queries overflow the depth limit"). Raise the limit for
    # this crate, as rustc's diagnostic suggests and as upstream already does
    # for app-server, exec and tui.
    postPatch = ''
      if ! grep -q 'recursion_limit' chatgpt/src/lib.rs; then
        substituteInPlace chatgpt/src/lib.rs \
          --replace-fail 'pub mod apply_command;' \
          $'#![recursion_limit = "256"]\n\npub mod apply_command;'
      fi
    '';

    inherit preBuild;

    # codex looks for codex-resources/bwrap and codex-code-mode-host next to
    # its own executable, so the real binaries live together in libexec/.
    postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      mkdir -p $out/libexec/codex/bin $out/libexec/codex/codex-resources
      ln -s ${lib.getExe bubblewrap} $out/libexec/codex/codex-resources/bwrap
      mv $out/bin/codex $out/bin/codex-code-mode-host $out/bin/logs_client \
        $out/libexec/codex/bin/

      makeWrapper $out/libexec/codex/bin/codex $out/bin/codex \
        --prefix PATH : ${lib.makeBinPath [ bubblewrap ]}
      ln -s ../libexec/codex/bin/codex-code-mode-host $out/bin/codex-code-mode-host
      ln -s ../libexec/codex/bin/logs_client $out/bin/logs_client
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
