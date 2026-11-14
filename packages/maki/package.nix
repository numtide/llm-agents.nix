{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  perl,
  python3,
  aws-lc,
  openssl,
  dbus,
  versionCheckHook,
  versionCheckHomeHook,
  unpinCargoMsrvHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "maki";
  version = "0.7.2";

  src = fetchFromGitHub {
    owner = "tontinton";
    repo = "maki";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zV+J2fMaa8JUWyP0veQT6Le9s0t4iHHmKWhmPXPrATQ=";
  };

  cargoHash = "sha256-Ld0mj+4URAUMjMyCfDW8dBK8dSse28c4FTcxkLh1mQY=";

  # unpinCargoMsrvHook: upstream pins rust-version = "1.99", newer than the
  # rustc in nixpkgs.
  nativeBuildInputs = [
    unpinCargoMsrvHook
    pkg-config
    perl
    python3
  ];

  buildInputs = [
    aws-lc
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ dbus ];

  env = {
    # isahc's native-tls-static would otherwise build OpenSSL from source.
    OPENSSL_NO_VENDOR = "1";
    AWS_LC_SYS_USE_SYSTEM = "1";
    # Upstream's fat LTO alone outlasts the CI build timeout.
    CARGO_PROFILE_RELEASE_LTO = "thin";
  };

  cargoBuildFlags = [
    "--package"
    "maki"
  ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Efficient AI coding agent extendable by neovim-like Lua plugins";
    homepage = "https://maki.sh";
    changelog = "https://github.com/tontinton/maki/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ colemickens ];
    mainProgram = "maki";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
  };
})
