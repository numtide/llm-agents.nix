{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
  sqlite,
  zstd,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tokscale";
  version = "4.22.0";

  src = fetchFromGitHub {
    owner = "junhoyeo";
    repo = "tokscale";
    tag = "v${finalAttrs.version}";
    hash = "sha256-A/xPUH5vGeMg8VZkf0XAYCFcCyXYLowv9TIo186FQt8=";
  };

  cargoHash = "sha256-8Msr80AVLkAYZZpVQPqb98JnoIR1EAiok/rMZ9KiCQE=";

  env = {
    OPENSSL_NO_VENDOR = 1;
    # Upstream's fat LTO with codegen-units=1 is a single-threaded link that
    # exceeds the aarch64 builder's 1200s timeout.
    CARGO_PROFILE_RELEASE_LTO = "off";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    openssl
    sqlite
    zstd
  ];

  # Tests need network access.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Usage Analytics";

  meta = {
    description = "CLI and TUI for AI token usage analytics";
    homepage = "https://github.com/junhoyeo/tokscale";
    changelog = "https://github.com/junhoyeo/tokscale/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "tokscale";
    platforms = lib.platforms.unix;
  };
})
