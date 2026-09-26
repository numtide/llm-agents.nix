{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  installShellFiles,
  hostname,
  versionCheckHook,
  versionCheckHomeHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "clauth";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "uwuclxdy";
    repo = "clauth";
    tag = "v${finalAttrs.version}";
    hash = "sha256-823ImaVDcXsaQ13EitckW4vxiUWDwNDLB9InT/gn4f0=";
  };

  cargoHash = "sha256-A9B6eA2Ws2PPBo/6jIAHfFkpAKwNGGACTYQzktnZDcY=";

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

  # daemon api tests shell out to `hostname` for the FQDN
  nativeCheckInputs = [ hostname ];

  preCheck = ''
    export HOME="$TMPDIR"
  '';

  # invalidated by the postPatch above
  checkFlags = [
    "--skip=update::tests::updates_enabled_when_env_is_other_value"
    "--skip=update::tests::updates_enabled_when_env_is_zero"
    "--skip=update::tests::updates_enabled_when_env_unset"
    "--skip=herdr::tests::heal_detached_reinstalls_once_and_throttles"
    "--skip=herdr::tests::heal_detached_fails_closed_without_the_shim_sentinel"
    "--skip=herdr::tests::heal_detached_respects_the_update_optout"
  ];

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
