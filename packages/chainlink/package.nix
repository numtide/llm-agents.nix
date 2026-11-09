{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  sqlite,
  versionCheckHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "chainlink";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "dollspace-gay";
    repo = "chainlink";
    tag = "chainlink-${version}";
    hash = "sha256-2n+cM1ADmeDrKZKjMY5Ct4mVxl38as4iu1Y4ZSCuBho=";
  };

  # The Rust crate is in the chainlink subdirectory
  cargoRoot = "chainlink";
  buildAndTestSubdir = "chainlink";

  cargoHash = "sha256-WmV6PRSuzdoCMXy4LMSMdHsSbI+A8jx89lwUt64DWmc=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ sqlite ];

  env.LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";

  # Upstream Cargo.toml version doesn't match release tags, and is sporadically
  # updated; replace it with the package version being careful to only update
  # within [package].
  postPatch = ''
    sed -i '/^\[package\]/,/^\[/{s/^version = ".*"/version = "${lib.versions.pad 3 version}"/}' chainlink/Cargo.toml
  '';

  # Tests require a writable filesystem
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Simple, lean issue tracker CLI designed for AI-assisted development";
    homepage = "https://github.com/dollspace-gay/chainlink";
    changelog = "https://github.com/dollspace-gay/chainlink/releases/tag/chainlink-${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ Chickensoupwithrice ];
    mainProgram = "chainlink";
    platforms = platforms.all;
  };
}
