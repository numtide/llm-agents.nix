{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  zig_0_15,
  makeWrapper,
  nodejs,
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

  # Upstream v0.2.8 does not compile with nixpkgs' default zig 0.16.0
  # (`error: discard of capture; omit it instead`). Pin zig_0_15 to package
  # the latest stable release without carrying a source compatibility patch.
  nativeBuildInputs = [
    zig_0_15.hook
    makeWrapper
  ];

  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];

  doCheck = true;

  # codex-auth shells out to Node.js for ChatGPT HTTP/usage queries
  # (CODEX_AUTH_NODE_EXECUTABLE in src/api/http_types.zig). Pin it so the
  # tool works without a system Node install.
  postInstall = ''
    wrapProgram $out/bin/codex-auth \
      --set CODEX_AUTH_NODE_EXECUTABLE ${lib.getExe nodejs}
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
