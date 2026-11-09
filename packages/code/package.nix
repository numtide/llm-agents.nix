{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  rustPlatform,
  pkg-config,
  aws-lc,
  symlinkJoin,
  rust-jemalloc-sys,
  libgit2,
  libssh2,
  oniguruma,
  openssl,
  sqlite,
  zlib,
  zstd,
  versionCheckHook,
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

let
  version = "0.6.196";

  src = fetchFromGitHub {
    owner = "just-every";
    repo = "code";
    tag = "v${version}";
    hash = "sha256-9UCPa5gFVL6KQCKviepn4kGhCBV8RPsWjQekD6JccC8=";
  };
in
rustPlatform.buildRustPackage {
  pname = "code";
  inherit version src;

  cargoHash = "sha256-tvice1qSse6VLnJNzqEBzJsiPqMYJKg3cbu34+0ovxU=";

  sourceRoot = "source/code-rs";

  cargoBuildFlags = [
    "--bin"
    "code"
    "--bin"
    "code-tui"
    "--bin"
    "code-exec"
  ];

  nativeBuildInputs = [
    installShellFiles
    pkg-config
  ];

  buildInputs = [
    openssl
    rust-jemalloc-sys
    libgit2
    libssh2
    oniguruma
    sqlite
    zlib
    zstd
  ];

  env = {
    CODE_VERSION = version;
    # aws-lc's compat openssl.pc would shadow openssl for openssl-sys, so it
    # is not in buildInputs; its own aws-lc.pc has no Cflags to detect it by.
    AWS_LC_SYS_SYSTEM_DIR = symlinkJoin {
      name = "aws-lc-prefix";
      paths = [
        (lib.getDev aws-lc)
        (lib.getLib aws-lc)
      ];
    };
    LIBGIT2_NO_VENDOR = "1";
    LIBSSH2_SYS_USE_PKG_CONFIG = "1";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    LIBZ_SYS_STATIC = "0";
    RUSTONIG_SYSTEM_LIBONIG = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
    JEMALLOC_OVERRIDE = "${lib.getLib rust-jemalloc-sys}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
  };

  preBuild = ''
    # Remove LTO and single codegen-unit to reduce peak memory usage.
    # The code-tui crate has a 42k-line source file (chatwidget.rs) that
    # causes the compiler to OOM on aarch64-linux with codegen-units=1.
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "fat"' 'lto = false' \
      --replace-fail 'codegen-units = 1' 'codegen-units = 16'
  '';

  doCheck = false;

  postInstall = ''
    # Add coder as an alias to avoid conflict with vscode
    ln -s code $out/bin/coder
  ''
  + lib.optionalString installShellCompletions ''
    installShellCompletion --cmd code \
      --bash <($out/bin/code completion bash) \
      --fish <($out/bin/code completion fish) \
      --zsh <($out/bin/code completion zsh)
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Fork of codex. Orchestrate agents from OpenAI, Claude, Gemini or any provider.";
    homepage = "https://github.com/just-every/code/";
    changelog = "https://github.com/just-every/code/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "code";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
  };
}
