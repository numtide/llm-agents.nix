{
  lib,
  stdenv,
  flake,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
  versionCheckHomeHook,
  git,
  lsof,
  procps,
  tmux,
}:

buildGoModule rec {
  pname = "agent-deck";
  version = "1.16.27";

  src = fetchFromGitHub {
    owner = "asheshgoplani";
    repo = "agent-deck";
    tag = "v${version}";
    hash = "sha256-yCtoCPOPiKDPZM4t/vtv4/Yn1Ut6hCc7E1a5uklmQm0=";
  };

  vendorHash = "sha256-AChAtXMmFDfJzlqnUpgkyD1KCmLGxkPZtKsD0+Tnt7E=";

  subPackages = [ "cmd/agent-deck" ];

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  doCheck = true;

  checkFlags = [
    "-short" # OBS-01 wiring test launches the full TUI otherwise
    (
      "-skip="
      + lib.concatStringsSep "|" (
        [
          "TestValidatePluginFlags_TelegramForkAccepted" # stale hardcoded plugin catalog
          "TestValidatePluginFlags_EmptyCatalogActionableError" # leaks state from the above
          "TestVerifyPromptConsumedAfterLaunch_UnsentFirstWindow_RetryThenConsumed_OneRetry_NoWarning" # timing-sensitive
          "TestWaitForFreshOutput_UniquePeerStillReads" # timing-sensitive
          "TestHealthRemoteExecJSONParity" # needs ssh client
          "TestRecallSearch_FederatedMergesAndLabels" # sqlite "database is locked" under parallel tests
          "TestIssue2388_CapabilitiesCarryProbe" # resets PATH to /usr/bin:/bin, losing cat
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          # lsof on live processes is denied by the sandbox
          "TestCleanupExcludesLiveProcessCWDInside"
          "TestCleanupRevalidatesRealityBeforeRemoval"
          "TestCleanupForceCannotOverrideRealityExclusions"
        ]
      )
    )
  ];

  preCheck = ''
    # Tests refuse paths under the passwd home (/build); keep TMPDIR dot-free
    # (breaks TestSessionContextJSONGolden) and symlink-resolved for darwin.
    tmp=$(cd /tmp && pwd -P)
    export TMPDIR=$(mktemp -d "$tmp/nix-XXXXXX")
    export HOME=$(mktemp -d "$tmp/nix-XXXXXX")
    export PATH="${git}/bin:$PATH"
  '';

  nativeCheckInputs = [
    lsof
    procps
    tmux
  ];

  doInstallCheck = true;

  ldflags = [
    "-s"
    "-w"
    "-X=main.Version=${version}"
  ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Your AI agent command center";
    homepage = "https://github.com/asheshgoplani/agent-deck";
    changelog = "https://github.com/asheshgoplani/agent-deck/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ garbas ];
    mainProgram = "agent-deck";
  };
}
