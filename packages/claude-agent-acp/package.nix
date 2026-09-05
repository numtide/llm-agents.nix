{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  claude-code,
}:

buildNpmPackage rec {
  npmDepsFetcherVersion = 2;
  pname = "claude-agent-acp";
  version = "0.75.1";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "claude-agent-acp";
    tag = "v${version}";
    hash = "sha256-LEubm7Ck22olYsP+l9tis9Qcw77fpy7gBT42P/Aj+KY=";
  };

  npmDepsHash = "sha256-LIzmtdsF7W2PxeD0X8ZiMeBEV67q+jLrpTJaLywl3s0=";
  makeCacheWritable = true;

  # Disable install scripts to avoid platform-specific dependency fetching issues
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  # The bundled @anthropic-ai/claude-agent-sdk platform packages ship a
  # prebuilt dynamically linked `claude` binary that is not usable on NixOS;
  # point the adapter at this flake's claude-code package instead, unless the
  # user overrides CLAUDE_CODE_EXECUTABLE themselves.
  postInstall = ''
    wrapProgram $out/bin/claude-agent-acp \
      --set-default CLAUDE_CODE_EXECUTABLE ${lib.getExe claude-code}
  '';

  passthru.category = "ACP Ecosystem";

  meta = with lib; {
    description = "An ACP-compatible coding agent powered by the Claude Code SDK (TypeScript)";
    homepage = "https://github.com/agentclientprotocol/claude-agent-acp";
    changelog = "https://github.com/agentclientprotocol/claude-agent-acp/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ ];
    mainProgram = "claude-agent-acp";
    platforms = platforms.all;
  };
}
