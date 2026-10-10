{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  perl,
  python3,
  openssl,
  dbus,
  versionCheckHook,
  versionCheckHomeHook,
  unpinCargoMsrvHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "maki";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "tontinton";
    repo = "maki";
    tag = "v${finalAttrs.version}";
    hash = "sha256-VdnGTPhRw8BMREIfSRCcddecZ8/9Ot8pF2mBADmnx0U=";
  };

  cargoHash = "sha256-GXHkaGcXJnC56QHBws70vj5FaBy3yVIHzPmCoZvSPdo=";

  # unpinCargoMsrvHook: upstream pins rust-version = "1.99", newer than the
  # rustc in nixpkgs.
  nativeBuildInputs = [
    unpinCargoMsrvHook
    pkg-config
    perl
    python3
  ];

  buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isLinux [ dbus ];

  # isahc's native-tls-static would otherwise build OpenSSL from source.
  env.OPENSSL_NO_VENDOR = "1";

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
