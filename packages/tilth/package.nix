{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  git,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tilth";
  version = "0.15.0";

  src = fetchFromGitHub {
    owner = "jahala";
    repo = "tilth";
    tag = "v${finalAttrs.version}";
    hash = "sha256-b+dmQSZPU424sllkFkz5vfhE9aBDCe6x5L25+e4Odr0=";
  };

  cargoHash = "sha256-vqPjUktsZVKzZb2Te9gGUNUzgzXYlIpY6o/SPLT6O/U=";

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];

  postInstall = ''
    wrapProgram $out/bin/tilth --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Tree-sitter-powered code reading CLI and MCP server for AI agents";
    homepage = "https://github.com/jahala/tilth";
    changelog = "https://github.com/jahala/tilth/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "tilth";
    platforms = platforms.unix;
  };
})
