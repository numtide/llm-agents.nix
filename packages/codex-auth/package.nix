{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  zig_0_17,
  bashInteractive,
  makeWrapper,
  nodejs,
  curl,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "codex-auth";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "loongphy";
    repo = "codex-auth";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Xgu4fclDvFbNUnzP0TZuwfVKdGBk98BIvPmY+U3XB10=";
  };

  nativeBuildInputs = [
    zig_0_17.hook
    makeWrapper
  ];

  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];

  doCheck = true;
  # zig segfaults compiling some tests with ReleaseSafe; upstream CI tests in Debug.
  zigCheckFlags = [ "-Doptimize=Debug" ];
  # the CLI shells out to curl for API-backed usage refresh; the tests exercise it
  nativeCheckInputs = [
    curl
    # completion tests rely on COMP_WORDBREAKS, which needs readline
    bashInteractive
  ];

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
