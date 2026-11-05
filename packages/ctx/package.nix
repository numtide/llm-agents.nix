{
  lib,
  fetchFromGitHub,
  flake,
  rustPlatform,
  installAgentSkills,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ctx";
  version = "2.4.0";

  src = fetchFromGitHub {
    owner = "ctxrs";
    repo = "ctx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-4XrRpWQkJJi3G9hfgcf4xeTxtb6615uLqEzxbXJnsU4=";
  };

  cargoHash = "sha256-N6e1N4SBlS7/5LFTXFKH+5yoc78TZlqYim2/k7QQLQs=";

  cargoBuildFlags = [
    "--package"
    "ctx"
  ];

  # CoreML acquisition tests fail in Nix sandbox.
  doCheck = false;

  nativeBuildInputs = [ installAgentSkills ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  # The plugin tree contains another copy of the same skill.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/ctx
  '';

  postInstallCheck = ''
    test -f "$out/share/skills/ctx/ctx/SKILL.md"
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Search the coding agent history already on your machine";
    homepage = "https://github.com/ctxrs/ctx";
    changelog = "https://github.com/ctxrs/ctx/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "ctx";
    platforms = lib.platforms.unix;
  };
})
