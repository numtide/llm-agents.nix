{
  lib,
  flake,
  rustPlatform,
  fetchCrate,
  pkg-config,
  oniguruma,
}:

rustPlatform.buildRustPackage rec {
  pname = "toon-format";
  version = "0.7.0";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-jB2gkLp/TMvgPz4izo8ZL7yd2utAdtCsNWB8I8GYv04=";
  };

  cargoHash = "sha256-j+UijiWYMLWeo3CM6J3q2PqEZRjHfG59JhdNAo3J/rA=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ oniguruma ];

  env.RUSTONIG_SYSTEM_LIBONIG = "1";

  cargoBuildFlags = [
    "--features"
    "cli"
  ];

  doCheck = false;

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Rust implementation of TOON - Token-Oriented Object Notation for LLM prompts";
    homepage = "https://github.com/toon-format/toon-rust";
    changelog = "https://github.com/toon-format/toon-rust/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ antono ];
    mainProgram = "toon";
    platforms = platforms.all;
  };
}
