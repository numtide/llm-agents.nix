{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  git,
  versionCheckHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "claw-code";
  version = "0.1.8-unstable-2026-10-23";

  src = fetchFromGitHub {
    owner = "ultraworkers";
    repo = "claw-code";
    rev = "8aab1d4e5410f9ab5e5e7f03c8a87de479e814ec";
    hash = "sha256-MkYG8rouqa7HYD+yvL2CbUsICsu5VW+rickb+kZfteE=";
  };

  sourceRoot = "source/rust";

  cargoHash = "sha256-+M6zFC+ZJPN29S8oWpK+CCH61A9xC9Qih9hOarnxqGs=";

  cargoBuildFlags = [
    "--package"
    "rusty-claude-cli"
  ];
  cargoTestFlags = cargoBuildFlags;

  # Upstream's #[cfg(test)] block in rusty-claude-cli/src/main.rs is broken
  # at this rev (ApiError::Api initializers missing the new suggested_action
  # field). The release binary compiles fine, so skip cargo test until
  # upstream catches up.
  doCheck = false;

  nativeCheckInputs = [ git ];

  preCheck = ''
    export HOME=$TMPDIR
  '';

  checkFlags = [
    # broken upstream at this rev: tool allow-list assertions out of sync with implementation
    "--skip=tests::rejects_unknown_allowed_tools"
    "--skip=tests::build_runtime_plugin_state_discovers_mcp_tools_and_surfaces_pending_servers"
    # integration harness expects scripted plugin fixtures not present in sandbox
    "--skip=clean_env_cli_reaches_mock_anthropic_service_across_scripted_parity_scenarios"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  # Upstream has no tagged release yet; we track an unstable rev. The binary
  # reports the Cargo workspace.package.version (e.g. 0.1.0), so compare
  # against that rather than our `0-unstable-<date>` derivation version.
  preVersionCheck = ''
    version=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1)
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Claude Code rewrite CLI built from the official claw-code Rust workspace";
    homepage = "https://github.com/ultraworkers/claw-code";
    changelog = "https://github.com/ultraworkers/claw-code/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "claw";
    platforms = lib.platforms.unix;
  };
}
