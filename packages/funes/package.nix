{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "funes";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "funes";
    tag = "v${finalAttrs.version}";
    hash = "sha256-4ZXOf8up7s1iCziQHmbNGTzjQkpQEVVlKhyWreanTu4=";
  };

  cargoHash = "sha256-EftPxiIZYoqMw7hPQrBneY5x0HbAo3z+1syC/OTg+w8=";

  postPatch = ''
    # Release CI stamps the version on the tag; the tagged Cargo.toml still
    # carries the dev label, which `funes --version` then reports.
    sed -i -E 's/^version = "[^"]*"$/version = "${finalAttrs.version}"/' Cargo.toml

    # lance-linalg's AVX-512 VNNI kernels do not compile with the rustc this
    # repo builds against; the AVX2 ones are left in place. See the patch.
    # fetchCargoVendor unpacks the crates.io crates under source-registry-0/ in
    # the build root, which unpackPhase cd's out of before postPatch runs.
    patch -p1 -d "$NIX_BUILD_TOP/$(stripHash "$cargoDeps")/source-registry-0" < ${./drop-lance-avx512-vnni.patch}
  '';

  # lance's protobuf schemas are generated at build time
  nativeBuildInputs = [ protobuf ];

  # lance's suite is slow and wants network fixtures
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Searchable memory of past AI agent sessions, exposed over MCP";
    homepage = "https://github.com/huggingface/funes";
    changelog = "https://github.com/huggingface/funes/releases/tag/v${finalAttrs.version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ happysalada ];
    mainProgram = "funes";
    platforms = platforms.unix;
  };
})
