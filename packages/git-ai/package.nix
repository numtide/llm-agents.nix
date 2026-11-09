{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  git,
  perl,
  installAgentSkills,
  pkg-config,
  openssl,
  sqlite,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "git-ai";
  version = "1.7.6";

  src = fetchFromGitHub {
    owner = "git-ai-project";
    repo = "git-ai";
    tag = "v${finalAttrs.version}";
    hash = "sha256-k2+X31apa1D9GBkdWNGvF06Sia0j2tZIGjYeQOFAFHE=";
  };

  cargoHash = "sha256-hoVm5IFXmGlEqEPrmsANkNUeavCmWjrJVLK6aknReyA=";

  nativeBuildInputs = [
    installAgentSkills
    pkg-config
    perl
  ];

  buildInputs = [
    openssl
    sqlite
  ];

  env = {
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    OPENSSL_NO_VENDOR = "1";
  };

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

  # Export the supported user workflows explicitly.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/ask
    installSkill skills/git-ai-search
    installSkill skills/prompt-analysis
  '';

  postInstallCheck = ''
    test -f "$out/share/skills/git-ai/ask/SKILL.md"
    test -f "$out/share/skills/git-ai/git-ai-search/SKILL.md"
    test -f "$out/share/skills/git-ai/prompt-analysis/SKILL.md"
  '';

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
