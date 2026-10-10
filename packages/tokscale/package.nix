{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tokscale";
  version = "4.18.0";

  src = fetchFromGitHub {
    owner = "junhoyeo";
    repo = "tokscale";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tVQRAUwvRi6Iaazqtu1kM84boFp5TEBuYS0PH0p5quY=";
  };

  cargoHash = "sha256-0yPl4+UjPJjVoTrsthSGBruog1SXuZTr7vUHlAxPigg=";

  env = {
    OPENSSL_NO_VENDOR = 1;
    # Upstream's fat LTO with codegen-units=1 is a single-threaded link that
    # exceeds the aarch64 builder's 1200s timeout.
    CARGO_PROFILE_RELEASE_LTO = "off";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

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
