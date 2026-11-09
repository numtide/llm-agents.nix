{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  aws-lc,
  dbus,
  versionCheckHook,
  unpinCargoMsrvHook,
  ...
}:

rustPlatform.buildRustPackage rec {
  pname = "nono";
  version = "0.81.0";

  src = fetchFromGitHub {
    owner = "nolabs-ai";
    repo = "nono";
    tag = "v${version}";
    hash = "sha256-0difjQr5qWP82ydktjBvWIvwqt4ndNuxj3WkWQj1Y+k=";
  };

  cargoHash = "sha256-GNcVJFAjZKPk0T14g0gL7FVj+HVAkjB4oTYf1naRRTk=";

  # `if let` guards in match arms require Rust >= 1.95; rewrite the single
  # use until nixpkgs ships a new enough rustc.
  patches = [ ./no-if-let-guard.patch ];

  # unpinCargoMsrvHook: upstream pins rust-version = "1.95" (unreleased MSRV
  # bump) but builds fine on the rustc in nixpkgs.
  nativeBuildInputs = [
    unpinCargoMsrvHook
    pkg-config
  ];

  # keyring uses sync-secret-service (dbus) on Linux, apple-native on Darwin
  buildInputs = [ aws-lc ] ++ lib.optionals stdenv.hostPlatform.isLinux [ dbus ];

  env.AWS_LC_SYS_USE_SYSTEM = "1";

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
  ];

  passthru.category = "Sandboxing & Isolation";

  meta = with lib; {
    description = "Kernel-enforced agent sandbox. Capability-based isolation with secure key management, atomic rollback, cryptographic immutable audit chain of provenance. Run your agents in a zero-trust environment.";
    homepage = "https://nono.sh/";
    changelog = "https://github.com/nolabs-ai/nono/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ pogobanane ];
    mainProgram = "nono";
    platforms = platforms.unix;
  };
}
