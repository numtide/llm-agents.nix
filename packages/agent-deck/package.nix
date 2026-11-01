{
  lib,
  stdenv,
  flake,
  bash,
  buildGo127Module,
  fetchFromGitHub,
  versionCheckHook,
  versionCheckHomeHook,
  git,
  lsof,
  ncurses,
  procps,
  tmux,
}:

buildGo127Module rec {
  pname = "agent-deck";
  version = "1.16.35";

  src = fetchFromGitHub {
    owner = "asheshgoplani";
    repo = "agent-deck";
    tag = "v${version}";
    hash = "sha256-5S0btEtXJloGtzNNXFaNDT603k8I1POxJISEZulNEwg=";
  };

  vendorHash = "sha256-8WZRtRXlsg/HuONcNnPjI8WjBkNlFeKgEBahAYyNsNI=";

  subPackages = [ "cmd/agent-deck" ];

  # launch-subagent.sh tests write stub agent-deck/jq scripts with a
  # /bin/bash shebang, which is absent from the linux sandbox.
  postPatch = ''
    substituteInPlace cmd/agent-deck/fanout_hint_docs_test.go \
      --replace-fail '#!/bin/bash' '#!${lib.getExe bash}'
  '';

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
          "TestIssue1576_WorktreeFinishSweepsNotifierState" # async event-bus flush races TempDir cleanup
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          # lsof on live processes is denied by the sandbox
          "TestCleanupExcludesLiveProcessCWDInside"
          "TestCleanupRevalidatesRealityBeforeRemoval"
          "TestCleanupForceCannotOverrideRealityExclusions"
          "TestAskSecretNeverLeaks" # samples /proc, which darwin lacks
          # mcp-proxy polls stdin with no requested events; darwin then never
          # reports POLLHUP, so EOF behind backpressure goes unnoticed
          "TestMCPProxyEOFWithInputBackpressure"
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          # the fake vault runs under the hardcoded PATH /usr/local/bin:/usr/bin:/bin,
          # where the linux sandbox has no tr or cat, so it never stores the value
          "TestAskSecretNeverLeaks"
          "TestAskSecretAcceptanceEndToEnd"
          "TestAskSecretRefusesExistingNameWithoutReplace"
          "TestAskDeliverAcceptsMacAppStdinBytes"
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
    ncurses # clear, used by the fake claude pane in the switch-settle tests
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
