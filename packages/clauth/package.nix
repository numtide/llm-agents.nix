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
  version = "0.17.0";

  src = fetchFromGitHub {
    owner = "uwuclxdy";
    repo = "clauth";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hbiBVUMZ0RO1+JqohtlwJ+NpBOl/jOZpkVDdEHShuNs=";
  };

  cargoHash = "sha256-A897WAfqn5YP09b1IKo8wV4avzzjNm6wUJ2tL6hHLE0=";

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
    # hardcodes /usr/bin/env, absent in the sandbox
    "--skip=daemon::api::terminal::tests::strip_session_env_removes_every_session_var"
    # 5s file-polling deadlines and wall-clock cadence asserts; flaky on loaded builders
    "--skip=daemon::api::terminal::tests::control_input_reaches_herdr_and_is_audited_without_its_bytes"
    "--skip=daemon::api::terminal::tests::frames_pipelined_behind_the_handshake_arrive"
    "--skip=codex_auth::tests::a_terminal_verdict_leaves_a_quarantine_record_and_a_rotation_clears_it"
    # the sandbox builds as root, so the "unwritable" memo path is writable
    "--skip=codex_auth::tests::an_unwritable_memo_sends_nothing_and_keeps_the_kick"
    "--skip=usage::scheduler::tests::oauth_and_provider_completions_clear_only_their_own_activity"
    "--skip=update::tests::updates_enabled_follows_the_saved_toggle"
    "--skip=herdr::tests::heal_detached_respects_the_saved_update_toggle"
    "--skip=mcp::startup_tests::startup_herdr_heal_follows_the_saved_update_toggle"
    "--skip=daemon::tests::tick_herdr_heal_follows_the_saved_update_toggle"
    # spawn and signal real processes, which the sandbox does not allow
    "--skip=daemon::gateway::tests::the_stub_teardown_never_signals_a_pid_that_no_longer_names_the_stub"
    "--skip=daemon::probe::tests::a_stop_leaving_no_daemon_stops_the_gateway_it_left"
    "--skip=daemon::probe::tests::stop_escalates_to_sigkill_past_the_wait"
    "--skip=daemon::probe::tests::stop_names_a_standby_that_took_over"
    "--skip=daemon::probe::tests::stop_terminates_the_daemon_and_leaves_the_singleton_free"
    "--skip=daemon::tests::start_runs_the_daemon_detached_into_its_log"
    "--skip=a_daemon_boot_runs_one_healthy_gateway_and_stops_it_on_sigterm"
    "--skip=the_gateways_output_lands_in_its_own_owner_only_log"
    "--skip=a_standby_daemon_spawns_nothing_until_it_takes_over"
    "--skip=a_daemon_stops_its_gateway_on_sigint_and_sighup_too"
    "--skip=a_daemon_that_inherited_sighup_ignored_keeps_running_on_hangup"
    # reads the process-global color tier without TierSandbox, so parallel
    # tests that pin the tier race with it
    "--skip=tui::render::services::tests::the_shunt_dot_maps_each_state_to_its_class"
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
