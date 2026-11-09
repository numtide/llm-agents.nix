{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  oniguruma,
  onnxruntime,
  openssl,
  sqlite,
  bun,
  bun2nixLib,
  versionCheckHook,
  versionCheckHomeHook,
}:
let
  hashes = builtins.fromJSON (builtins.readFile ./hashes.json);

  # Extract web frontend source from the repo
  icm-web-src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "icm";
    tag = "icm-v${hashes.version}";
    hash = hashes.hash;
  };

  # Build web frontend as separate derivation with bun2nix
  icm-web = stdenv.mkDerivation {
    pname = "icm-web";
    version = hashes.version;

    src = icm-web-src;
    sourceRoot = "source/crates/icm-cli/web";

    nativeBuildInputs = [
      bun
      bun2nixLib.hook
    ];

    bunDeps = bun2nixLib.fetchBunDeps {
      bunNix = ./bun.nix;
    };

    dontUseBunBuild = true;
    dontUseBunInstall = true;

    buildPhase = ''
      runHook preBuild
      bun run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/* $out/
      runHook postInstall
    '';
  };
in
rustPlatform.buildRustPackage {
  pname = "icm";
  version = hashes.version;

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "icm";
    tag = "icm-v${hashes.version}";
    hash = hashes.hash;
  };

  cargoHash = hashes.cargoHash;

  cargoBuildFlags = [
    "--package"
    "icm-cli"
    "--features"
    "web"
  ];

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    oniguruma
    onnxruntime
    openssl
    sqlite
  ];

  env = {
    ORT_LIB_LOCATION = "${lib.getLib onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
    LIBRARY_PATH = "${lib.getLib onnxruntime}/lib";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    RUSTONIG_SYSTEM_LIBONIG = "1";
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    RUSTFLAGS = "-C link-arg=-Wl,-headerpad_max_install_names";
  };

  preBuild = ''
    mkdir -p crates/icm-cli/web/dist
    cp -r ${icm-web}/* crates/icm-cli/web/dist/
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    install_name_tool -add_rpath "${lib.getLib onnxruntime}/lib" $out/bin/icm
  '';

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru = {
    inherit icm-web;
    category = "Memory & Code Intelligence";
  };

  meta = with lib; {
    description = "Persistent memory for AI agents with hybrid search, temporal decay, and multilingual embeddings";
    homepage = "https://github.com/rtk-ai/icm";
    changelog = "https://github.com/rtk-ai/icm/releases/tag/icm-v${hashes.version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ csanthiago ];
    mainProgram = "icm";
    platforms = platforms.unix;
  };
}
