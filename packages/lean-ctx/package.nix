{
  lib,
  fetchFromGitHub,
  rustPlatform,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "lean-ctx";
  version = "3.5.12";

  src = fetchFromGitHub {
    owner = "yvgude";
    repo = "lean-ctx";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  sourceRoot = "${src.name}/rust";

  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  # Build with default features: tree-sitter, embeddings, http-server, secure-update
  # Excluding cloud-server feature as it requires additional database dependencies
  buildFeatures = [
    "tree-sitter"
    "embeddings"
    "http-server"
    "secure-update"
  ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Context Runtime for AI Agents with CCP + TDD. Shell Hook + MCP Server. 57 MCP tools, 10 read modes, 95+ shell patterns, cross-session memory";
    homepage = "https://leanctx.com";
    changelog = "https://github.com/yvgude/lean-ctx/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ ];
    mainProgram = "lean-ctx";
    platforms = platforms.unix;
  };
}
