{
  lib,
  flake,
  buildGo127Module,
  fetchFromGitHub,
  unpinGoModVersionHook,
  versionCheckHook,
}:

buildGo127Module rec {
  pname = "agent-manager";
  version = "0.42.0";

  src = fetchFromGitHub {
    owner = "YoanWai";
    repo = "agent-manager";
    tag = "v${version}";
    hash = "sha256-c/MboSuey1H/ya/NlEIngvFKbvDcjVAyBnSixX/vcS4=";
  };

  # Upstream go.mod pins a newer Go patch release than nixpkgs ships.
  nativeBuildInputs = [ unpinGoModVersionHook ];

  vendorHash = "sha256-H3BqgmaeC5VtXQoDNPkjs6NIU+znZIyXdR4f0keRzxU=";

  subPackages = [ "." ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Terminal UI that runs coding-agent CLIs side by side, each in its own tmux session";
    homepage = "https://agent-manager.dev";
    changelog = "https://github.com/YoanWai/agent-manager/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ YoanWai ];
    mainProgram = "agent-manager";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
