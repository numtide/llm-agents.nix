{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  rustPlatform,
  pkg-config,
  lld,
  aws-lc,
  rust-jemalloc-sys,
  libgit2,
  oniguruma,
  rust-bindgen,
  sqlite,
  zlib,
  zstd,
  bubblewrap,
  ripgrep,
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
    # nixpkgs does. Line tables for codex-core/codex-tui add more memory
    # and the aarch64 builders OOM-kill rustc when many big crates compile
    # in parallel, so drop debuginfo and cap cargo's job count.
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "thin"' "" \
      --replace-fail 'codegen-units = 4' "" \
      --replace-fail 'debug = "line-tables-only"' 'debug = "none"'
    if [ "$NIX_BUILD_CORES" -gt 8 ]; then
      export NIX_BUILD_CORES=8
    fi
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

  packageManifest = builtins.toJSON {
    layoutVersion = 1;
    inherit version;
    target = stdenv.hostPlatform.rust.rustcTarget;
    variant = "codex";
    entrypoint = "bin/codex";
    resourcesDir = "codex-resources";
    pathDir = "codex-path";
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
      pkg-config
      rust-bindgen
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      # Unable to find libclang: "couldn't find any valid shared libraries matching: ['libclang.dylib']
      rustPlatform.bindgenHook
    ];

    buildInputs = [
      aws-lc
      rust-jemalloc-sys
      libgit2
      oniguruma
      sqlite
      zlib
      zstd
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ libcap ];

    env = {
      RUSTY_V8_ARCHIVE = librusty_v8;
      # openssl-sys also builds against aws-lc (through its compat openssl.pc):
      # linking both libcrypto copies leaves openssl symbols unresolved.
      AWS_LC_SYS_USE_SYSTEM = "1";
      LIBGIT2_NO_VENDOR = "1";
      LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
      LIBZ_SYS_STATIC = "0";
      RUSTONIG_SYSTEM_LIBONIG = "1";
      ZSTD_SYS_USE_PKG_CONFIG = "1";
      JEMALLOC_OVERRIDE = "${lib.getLib rust-jemalloc-sys}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
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

    # The daemon would copy the whole package (~550 MB) into ~/.codex and let
    # upstream's updater replace it. Run it from the store instead.
    patches = [ ./daemon-nix-store.patch ];

    # webpki-roots 1.0.10 drops the emSign roots and rustls-webpki 0.103.16
    # rejects the revoked eMudhra intermediates. Upstream main has both;
    # drop this once a release ships them.
    cargoPatches = lib.optional (lib.versionOlder version "0.164.0") ./webpki-bump.patch;

    # The future returned by `connectors::list_connectors` nests deeply
    # enough that computing its layout exceeds rustc's default query depth
    # limit of 128 ("queries overflow the depth limit"). Raise the limit for
    # this crate, as rustc's diagnostic suggests and as upstream already does
    # for app-server, exec and tui.
    postPatch = ''
      substituteInPlace app-server-daemon/src/prepare_install.rs \
        --subst-var-by storeDir ${builtins.storeDir} \
        --subst-var out
      if ! grep -q 'recursion_limit' chatgpt/src/lib.rs; then
        substituteInPlace chatgpt/src/lib.rs \
          --replace-fail 'pub mod apply_command;' \
          $'#![recursion_limit = "256"]\n\npub mod apply_command;'
      fi
    '';

    inherit preBuild;

    # The daemon refuses to start unless it finds upstream's package layout
    # around its executable (#9887).
    postFixup = ''
      mkdir -p $out/libexec/codex/{bin,codex-path,codex-resources}
      mv $out/bin/codex $out/bin/codex-code-mode-host $out/bin/logs_client \
        $out/libexec/codex/bin/
      ln -s ${lib.getExe ripgrep} $out/libexec/codex/codex-path/rg
      printf '%s\n' ${lib.escapeShellArg packageManifest} \
        > $out/libexec/codex/codex-package.json

      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        ln -s ${lib.getExe bubblewrap} $out/libexec/codex/codex-resources/bwrap
      ''}
      ln -s ../libexec/codex/bin/codex $out/bin/codex
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
