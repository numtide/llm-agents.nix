{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  zig,
  makeWrapper,
  nodejs,
  curl,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "codex-auth";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "loongphy";
    repo = "codex-auth";
    tag = "v${finalAttrs.version}";
    hash = "sha256-TrJtVP4gRdupx6StKWc2PIXoVnnlFMUqFw6JtEmWqZ4=";
  };

  nativeBuildInputs = [
    zig.hook
    makeWrapper
  ];

  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];

  doCheck = true;
  # the CLI shells out to curl for API-backed usage refresh; the tests exercise it
  nativeCheckInputs = [ curl ];

  # codex-auth shells out to Node.js for ChatGPT HTTP/usage queries
  # (CODEX_AUTH_NODE_EXECUTABLE in src/api/http_types.zig). Pin it so the
  # tool works without a system Node install.
  postInstall = ''
    wrapProgram $out/bin/codex-auth \
      --set CODEX_AUTH_NODE_EXECUTABLE ${lib.getExe nodejs} \
      --prefix PATH : ${lib.makeBinPath [ curl ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "CLI tool for switching Codex accounts";
    homepage = "https://github.com/loongphy/codex-auth";
    changelog = "https://github.com/loongphy/codex-auth/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ xbpk3t ];
    mainProgram = "codex-auth";
    platforms = platforms.unix;
  };
})
