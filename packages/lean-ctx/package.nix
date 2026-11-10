{
  lib,
  stdenv,
  flake,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  aws-lc,
  symlinkJoin,
  rust-jemalloc-sys,
  openssl,
  sqlite,
  zstd,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "lean-ctx";
  version = "3.12.2";

  src = fetchFromGitHub {
    owner = "yvgude";
    repo = "lean-ctx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-s/uuw6CNhHiW+Yn2OksUi/QXANsu0CoQArA50UfBsfw=";
  };

  cargoRoot = "rust";
  buildAndTestSubdir = "rust";
  cargoHash = "sha256-e/oJFb91r7oRgiKAkcZB5uHNzZV2QIgOQ7nUYKQQAGc=";

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    openssl
    rust-jemalloc-sys
    sqlite
    zstd
  ];

  # Upstream's fat LTO with codegen-units=1 is a single-threaded link that
  # exceeds the aarch64 builder's 1200s timeout.
  env = {
    CARGO_PROFILE_RELEASE_LTO = "off";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
    # aws-lc's compat openssl.pc would shadow openssl for openssl-sys, so it
    # is not in buildInputs; its own aws-lc.pc has no Cflags to detect it by.
    AWS_LC_SYS_SYSTEM_DIR = symlinkJoin {
      name = "aws-lc-prefix";
      paths = [
        (lib.getDev aws-lc)
        (lib.getLib aws-lc)
      ];
    };
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    OPENSSL_NO_VENDOR = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
    JEMALLOC_OVERRIDE = "${lib.getLib rust-jemalloc-sys}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
  };

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = {
    description = "Context OS for AI development — compression, memory, and routing for LLM context";
    homepage = "https://github.com/yvgude/lean-ctx";
    changelog = "https://github.com/yvgude/lean-ctx/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ csanthiago ];
    mainProgram = "lean-ctx";
    platforms = lib.platforms.unix;
  };
})
