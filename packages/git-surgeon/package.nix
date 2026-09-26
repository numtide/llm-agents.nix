{
  lib,
  fetchFromGitHub,
  rustPlatform,
  installAgentSkills,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "git-surgeon";
  version = "0.1.17";

  src = fetchFromGitHub {
    owner = "raine";
    repo = "git-surgeon";
    tag = "v${finalAttrs.version}";
    hash = "sha256-SeXHYZwhwvkYxFHW694Cp1VKKeehxgOdfKqShuPI7M4=";
  };

  cargoHash = "sha256-PbhASsdDxmVcIzV+oHIbpX70zjSeNvkwGcbhQRi88rE=";

  nativeBuildInputs = [ installAgentSkills ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Utilities";

  meta = {
    description = "Git primitives for autonomous coding agents";
    longDescription = ''
      git-surgeon gives AI agents surgical control over git changes without
      interactive prompts. Stage, unstage, or discard individual hunks. Commit
      hunks directly with line-range precision. Restructure history by
      splitting commits or folding fixes into earlier ones.
    '';
    homepage = "https://github.com/raine/git-surgeon";
    changelog = "https://github.com/raine/git-surgeon/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "git-surgeon";
    maintainers = with lib.maintainers; [ sei40kr ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
  };
})
