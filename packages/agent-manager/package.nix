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
  version = "0.50.0";

  src = fetchFromGitHub {
    owner = "YoanWai";
    repo = "agent-manager";
    tag = "v${version}";
    hash = "sha256-qku1XRy0v4Rs9u2bw5LGbrJKtxYDp/8c7cjcAmeZEoM=";
  };

  vendorHash = "sha256-mDZQjHs2HLW2fJS6QEU9JvGCUWuTULUfR9W2xB20T6k=";

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
