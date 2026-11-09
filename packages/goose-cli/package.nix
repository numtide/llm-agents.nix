{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  cmake,
  aws-lc,
  oniguruma,
  openssl,
  sqlite,
  zstd,
  libxcb,
  dbus,
  versionCheckHook,
  cacert,
  callPackage,
  librusty_v8 ? callPackage ./librusty_v8.nix {
    inherit (callPackage ./fetchers.nix { }) fetchLibrustyV8;
  },
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
in
rustPlatform.buildRustPackage rec {
  pname = "goose-cli";
  inherit (versionData) version cargoHash;

  src = fetchFromGitHub {
    # Upstream moved from block/goose to aaif-goose/goose.
    owner = "aaif-goose";
    repo = "goose";
    tag = "v${version}";
    inherit (versionData) hash;
  };

  nativeBuildInputs = [
    pkg-config
    # llama-cpp-sys-2 builds llama.cpp via cmake and generates bindings with
    # bindgen, which needs libclang at build time.
    cmake
    rustPlatform.bindgenHook
  ];

  # The cmake setup hook would otherwise try to configure the cargo project
  # itself; llama-cpp-sys-2 invokes cmake on its own.
  dontUseCmakeConfigure = true;

  buildInputs = [
    aws-lc
    oniguruma
    openssl
    sqlite
    zstd
    libxcb
    dbus
  ];

  # reqwest-based tests need a CA bundle to construct HTTP clients.
  nativeCheckInputs = [ cacert ];

  env = {
    # The v8 package will try to download a `librusty_v8.a` release at build time to our read-only filesystem
    # To avoid this we pre-download the file and export it via RUSTY_V8_ARCHIVE
    RUSTY_V8_ARCHIVE = librusty_v8;
    AWS_LC_SYS_USE_SYSTEM = "1";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    RUSTONIG_SYSTEM_LIBONIG = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
  };

  # Build only the CLI package
  cargoBuildFlags = [
    "--package"
    "goose-cli"
  ];

  # Enable tests with proper environment
  doCheck = true;
  checkPhase = ''
    export HOME=$(mktemp -d)
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export XDG_CACHE_HOME=$HOME/.cache
    mkdir -p $XDG_CONFIG_HOME $XDG_DATA_HOME $XDG_STATE_HOME $XDG_CACHE_HOME

    # Run tests for goose-cli package only.
    # test_verify_provenance_warns_on_missing_attestation needs network access.
    # untracked_enumeration_stays_in_opened_root_after_swap shells out to git,
    # which is not available in the sandbox.
    cargo test --package goose-cli --release -- \
      --skip commands::update::tests::test_verify_provenance_warns_on_missing_attestation \
      --skip commands::review::handler::tests::untracked_enumeration_stays_in_opened_root_after_swap
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "CLI for Goose - a local, extensible, open source AI agent that automates engineering tasks";
    homepage = "https://github.com/aaif-goose/goose";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "goose";
  };
}
