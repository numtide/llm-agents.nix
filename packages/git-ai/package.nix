{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  git,
  perl,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "git-ai";
  version = "1.6.24-next-3c41054";

  src = fetchFromGitHub {
    owner = "git-ai-project";
    repo = "git-ai";
    tag = "v${finalAttrs.version}";
    hash = "sha256-EA1KgXtb6MmwpkrPFBoEbJaKIRfnjvgcXVmwB4jGIgc=";
  };

  cargoHash = "sha256-GYDFOSxl1Kkol1XOcpkqNWcSTTsJWiRhpZGMrVA+H8c=";

  nativeBuildInputs = [ perl ];

  postPatch = ''
    substituteInPlace src/config.rs \
      --replace-fail '"/usr/bin/git"' '"${git}/bin/git"'
    substituteInPlace src/authorship/virtual_attribution.rs \
      --replace-fail 'Command::new("git")' 'Command::new("${git}/bin/git")'
  '';

  cargoBuildFlags = [
    "--bin"
    "git-ai"
  ];

  # Upstream's full test suite manages per-test daemons and test-only binaries,
  # and the full library suite exits abnormally in the Nix sandbox.  Run a pure
  # unit-test subset that does not require daemon/socket orchestration.
  cargoTestFlags = [
    "--lib"
    "uuid::"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "version";

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Git extension for tracking AI-generated code in repositories";
    homepage = "https://github.com/git-ai-project/git-ai";
    changelog = "https://github.com/git-ai-project/git-ai/releases/tag/v${finalAttrs.version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "git-ai";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
