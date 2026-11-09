{
  lib,
  stdenv,
  flake,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  aws-lc,
  jemalloc,
  oniguruma,
  openssl,
  sqlite,
  zstd,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "jcode";
  version = "0.99.1";

  src = fetchFromGitHub {
    owner = "1jehuang";
    repo = "jcode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-U6M+oLfx/M0cbZ68OppBtwqg6BuSXZZn4m1shWIYPi0=";
  };

  cargoHash = "sha256-jKalXYUIm1FIaDfncFzDW/4eGMlxwjkSvNyv2dwdE24=";

  # .cargo/config.toml caps builds at 4 jobs; let Nix parallelism decide.
  postPatch = ''
    rm .cargo/config.toml
  '';

  # aws-lc-sys (rustls provider) needs cmake; imap's default native-tls
  # backend links against system openssl.
  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    aws-lc
    jemalloc
    oniguruma
    openssl
    sqlite
    zstd
  ];

  # Make the embedded version string a release one ("vX.Y.Z") instead of a
  # dev one; the build script falls back to "unknown" git metadata, which is
  # fine for tarball builds.
  env = {
    JCODE_RELEASE_BUILD = "1";
    AWS_LC_SYS_USE_SYSTEM = "1";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    RUSTONIG_SYSTEM_LIBONIG = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
    JEMALLOC_OVERRIDE = "${lib.getLib jemalloc}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
  };

  # Test suite needs network access, provider credentials and a TTY.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "RAM-efficient coding agent TUI with multi-model support and swarm coordination";
    homepage = "https://github.com/1jehuang/jcode";
    changelog = "https://github.com/1jehuang/jcode/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "jcode";
    platforms = platforms.unix;
  };
})
