{
  lib,
  fetchFromGitHub,
  rustPlatform,
  versionCheckHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "plannotator-tui";
  version = "0.9.4";

  src = fetchFromGitHub {
    owner = "plannotator";
    repo = "plannotator-tui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-oJ+AMl2G9m/hxFJLwiN6CQ9urhyhK0w6VEcbnpUgQv0=";
  };

  cargoHash = "sha256-EK3iCT+VJQ/1Sjhdt06nc1pUdo0B6tPBjbjSV9jsRKY=";

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Code Review";

  meta = {
    description = "Annotate Markdown in the terminal and send feedback to coding agents";
    homepage = "https://github.com/plannotator/plannotator-tui";
    changelog = "https://github.com/plannotator/plannotator-tui/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = [ lib.maintainers.ramblurr ];
    mainProgram = "plannotator-tui";
    platforms = lib.platforms.unix;
  };
})
