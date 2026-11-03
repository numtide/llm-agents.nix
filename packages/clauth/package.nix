{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  installShellFiles,
  versionCheckHook,
  versionCheckHomeHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "clauth";
  version = "0.18.1";

  src = fetchFromGitHub {
    owner = "uwuclxdy";
    repo = "clauth";
    tag = "v${finalAttrs.version}";
    hash = "sha256-FPNxwJLgLNdhBfWxCE6wqwoGKf6VIMILuErxz9IOsMs=";
  };

  cargoHash = "sha256-NqJaOdULHaB/PIuXQx479qNYiCJk9r+6BegTohlZSMU=";

  nativeBuildInputs = [ installShellFiles ];

  # disable the self-updater (equivalent to CLAUTH_NO_UPDATE=1)
  postPatch = ''
    substituteInPlace src/update.rs \
      --replace-fail 'env::var(NO_UPDATE_ENV).as_deref() != Ok("1")' 'false'
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd clauth \
      --bash <("$out/bin/clauth" completions bash) \
      --fish <("$out/bin/clauth" completions fish) \
      --zsh <("$out/bin/clauth" completions zsh)
  '';

  # Many tests race on process-global state (PATH, colour tier, one-shot log
  # latches) and fail at random on loaded builders.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Claude Code Ecosystem";

  meta = {
    description = "Claude Code multi-account manager and usage monitor (CLI, TUI and MCP cross-account delegation)";
    homepage = "https://github.com/uwuclxdy/clauth";
    changelog = "https://github.com/uwuclxdy/clauth/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ aldoborrero ];
    mainProgram = "clauth";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = lib.platforms.unix;
  };
})
