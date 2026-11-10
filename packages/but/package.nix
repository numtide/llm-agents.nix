{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  unpinCargoMsrvHook,
  openssl,
  sqlite,
  zstd,
  dbus,
  stdenv,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "but";
  version = "0.23.3";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    tag = "release/${finalAttrs.version}";
    hash = "sha256-QFpAE5Kd/dT5aSqhG5h+3k+f6F93vSzt5Z3VmUNPQk0=";
  };

  cargoHash = "sha256-Q25+Fk9YVRkn0NxepjWvk7NZrdcq5lP6en+s6QR2xdM=";

  # Upstream enables git2's `unstable-sha256`, so libgit2-sys probes the
  # `libgit2-experimental` pkg-config module, which nixpkgs does not ship;
  # LIBGIT2_NO_VENDOR (set by cargoSetupHook) would then abort the build.
  dontCargoUseSystemLibs = true;

  # Upstream pins a specific stable channel; allow building with nixpkgs' rustc.
  postPatch = ''
    rm -f rust-toolchain.toml
    # nixpkgs' rustc uses LLVM 21, whose vpdpbusd.256 signature does not match
    # core::arch's; drop adler32furious' VNNI kernels until rustc uses LLVM 22.
    patch -p1 -d "$cargoDepsCopy/source-registry-0/adler32furious-0.1.1" < ${./adler32furious-llvm21.patch}
  '';

  nativeBuildInputs = [
    pkg-config
    unpinCargoMsrvHook
  ];

  buildInputs = [
    openssl
    sqlite
    zstd
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    dbus
  ];

  env = {
    # Upstream reads the user-facing version from $VERSION at build time
    # (set by their release pipeline); without it `but --version` reports "dev".
    VERSION = finalAttrs.version;
    # CHANNEL=release makes the binary use the production app identifier.
    CHANNEL = "release";
    OPENSSL_NO_VENDOR = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
    # Avoid generating TypeScript bindings into the source tree during build.
    TS_RS_EXPORT_DIR = "/build/ts-rs";
  };

  cargoBuildFlags = [
    "--package=but"
  ];
  # Signal that the binary is distributed via a package manager so it
  # disables self-update / `but update install` codepaths.
  buildFeatures = [ "but/packaged-but-distribution" ];

  # The workspace test suite requires git fixtures, network access and the
  # full Tauri/GUI stack; the CLI itself is exercised via versionCheckHook.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "GitButler CLI - virtual branches and AI-assisted Git workflow from the terminal";
    homepage = "https://github.com/gitbutlerapp/gitbutler";
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/${finalAttrs.version}";
    license = flake.lib.licenses.fsl11Mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mic92 ];
    mainProgram = "but";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
