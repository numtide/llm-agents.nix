{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "multica";
  version = "0.4.43";

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    tag = "v${finalAttrs.version}";
    hash = "sha256-M/Zc9Bc/IKK2Dwc9TbNGz3OCDARmQQOXRTLPYw9iLZs=";
  };

  sourceRoot = "${finalAttrs.src.name}/server";
  subPackages = [ "cmd/multica" ];

  vendorHash = "sha256-a3khoppmpS5o+ZJqWjcFwLKpUSXfTG9P5/4lLdBr+tY=";

  ldflags = [ "-X main.version=${finalAttrs.version}" ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Command-line interface for the Multica platform";
    homepage = "https://github.com/multica-ai/multica";
    changelog = "https://github.com/multica-ai/multica/releases/tag/v${finalAttrs.version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "multica";
    platforms = lib.platforms.unix;
  };
})
