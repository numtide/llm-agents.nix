{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  oniguruma,
  onnxruntime,
  openssl,
  zstd,
  stdenv,
  darwinMinVersionHook,
}:
rustPlatform.buildRustPackage rec {
  pname = "ck";
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "BeaconBay";
    repo = "ck";
    tag = version;
    hash = "sha256-VI8nqIAlcynSHvs5BbXg5numYaa4NwppvLhv1gbN9yk=";
  };

  cargoHash = "sha256-lVE8D1EEj2r7ZmAJPlALsstr41rMzIQr/C8ZCr4Um44=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    oniguruma
    onnxruntime
    openssl
    zstd
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    (darwinMinVersionHook "11.0")
  ];

  cargoBuildFlags = [ "--package=ck-search" ];

  # Tests require onnxruntime at runtime via @rpath
  doCheck = false;

  env = {
    # Use system onnxruntime instead of downloading binaries
    ORT_LIB_LOCATION = "${lib.getLib onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
    RUSTONIG_SYSTEM_LIBONIG = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
  };

  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    install_name_tool -add_rpath "${lib.getLib onnxruntime}/lib" $out/bin/ck
  '';

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Local first semantic and hybrid BM25 grep / search tool for use by AI and humans!";
    homepage = "https://github.com/BeaconBay/ck";
    changelog = "https://github.com/BeaconBay/ck/releases/tag/${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "ck";
  };
}
