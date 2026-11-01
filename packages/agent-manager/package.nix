{
  lib,
  flake,
  buildGo127Module,
  fetchFromGitHub,
  makeWrapper,
  tmux,
  versionCheckHook,
}:

buildGo127Module rec {
  pname = "agent-manager";
  version = "0.46.0";

  src = fetchFromGitHub {
    owner = "YoanWai";
    repo = "agent-manager";
    tag = "v${version}";
    hash = "sha256-0ZFQaVhs004LR8VAkZR/wmOtaz8aUUCH+K1J1C9F0Hs=";
  };

  vendorHash = "sha256-5wkFrMibi83C92k3KVgAb+R0hOyXQXAwpewkb1zbYfE=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-X=main.version=${version}"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/bin/agent-manager --suffix PATH : ${lib.makeBinPath [ tmux ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Terminal UI that runs coding-agent CLIs side by side, each in its own tmux session";
    homepage = "https://agent-manager.dev";
    changelog = "https://github.com/YoanWai/agent-manager/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ YoanWai ];
    mainProgram = "agent-manager";
    platforms = lib.platforms.unix;
  };
}
