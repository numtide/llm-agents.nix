{
  lib,
  flake,
  buildGoModule,
  go-bin,
  fetchFromGitHub,
  makeWrapper,
  tmux,
  versionCheckHook,
}:

# go.mod requires go >= 1.27.4; nixpkgs ships 1.27.3 so far.
(buildGoModule.override { go = go-bin; }) rec {
  pname = "agent-manager";
  version = "0.48.1";

  src = fetchFromGitHub {
    owner = "YoanWai";
    repo = "agent-manager";
    tag = "v${version}";
    hash = "sha256-c4HYPzd8OhxGAx/gXNdrEZUc6c5tevCQIDpiOLfQcZE=";
  };

  vendorHash = "sha256-90wZZEXjRqzZzyCGsu6/2cs6STDIFb031L1TbM1zekw=";

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
