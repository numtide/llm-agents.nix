{
  lib,
  rustPlatform,
  fetchFromGitHub,
  flake,
  git,
  jq,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gitagent";
  version = "3.0.0";

  src = fetchFromGitHub {
    owner = "open-gitagent";
    repo = "gitagent";
    tag = "v${finalAttrs.version}";
    hash = "sha256-b7JosG1h1+X5mnKNpo8C8VOgIDwFYdvfAewv9GuViuI=";
  };

  cargoHash = "sha256-kvhi4yr2nJqwrKdQHNuAdOMeibhI3I47ArtuoT28y30=";

  cargoBuildFlags = [
    "--package"
    "gitagent-cli"
  ];
  cargoTestFlags = finalAttrs.cargoBuildFlags;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    git
    jq
  ];

  postInstall = ''
    wrapProgram $out/bin/gitagent --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Universal git-native multimodal AI agent";
    homepage = "https://github.com/open-gitagent/gitagent";
    changelog = "https://github.com/open-gitagent/gitagent/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "gitagent";
    platforms = lib.platforms.all;
  };
})
