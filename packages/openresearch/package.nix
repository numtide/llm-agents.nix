{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchpatch,
  makeWrapper,
  installAgentSkills,
  mkUpdater,
  bash,
  coreutils,
  gawk,
  git,
  gnutar,
  openssh,
  procps,
  python3,
  xdg-utils,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  hashes = builtins.fromJSON (builtins.readFile ./hashes.json);
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "openresearch";
  inherit (hashes) version cargoHash;

  src = fetchFromGitHub {
    owner = "alphaXiv";
    repo = "OpenResearch";
    tag = "v${finalAttrs.version}";
    inherit (hashes) hash;
  };

  patches = [
    # Pending upstream #698; remove once a release includes the readiness EINTR fix.
    (fetchpatch {
      url = "https://github.com/alphaXiv/OpenResearch/commit/f53d9b0e8956ab14cbc85314c7780d697e8f2009.patch";
      hash = "sha256-MrfzGMAj6Gw4JMajr18wytL/J9WJrTRTvHZbUTtT6zc=";
    })
  ];

  nativeBuildInputs = [
    makeWrapper
    installAgentSkills
  ];

  # Export the CLI guide, not the agent-specific runtime skill collection.
  dontInstallAgentSkills = true;

  postPatch = ''
    substituteInPlace $(grep -rl '#!/bin/sh' src) \
      --replace-fail '#!/bin/sh' '#!${bash}/bin/sh'
    substituteInPlace src/commands/up.rs \
      --replace-fail '"sh",' '"${bash}/bin/sh",'
    # The fake ssh in these tests calls cat and, for `ssh -G`, /usr/bin/ssh;
    # neither exists in the sandbox.
    substituteInPlace tests/compute_cli.rs \
      --replace-fail '{}:/usr/bin:/bin"' '{}:${coreutils}/bin"' \
      --replace-fail 'exec /usr/bin/ssh' 'exec ${openssh}/bin/ssh'
  '';

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  checkFlags = [
    # 2s wall-clock assertion on SIGTERM handling; flaky on loaded builders
    "--skip=jobs::ssh::tests::host_wrapper_finishes_cooperative_term_promptly"
    # needs live ssh control sockets under /tmp, which the sandbox lacks
    "--skip=jobs::ssh::sharing::tests::native_config_shares_only_matching_live_sockets_and_preserves_user_settings"
    # runs /bin/sh, which the Linux sandbox lacks
    "--skip=jobs::rental::tests::rental_bootstrap_runs_bash_syntax_through_the_posix_login_shell"
  ]
  # child process is not reaped within the test's deadline in the darwin sandbox
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "--skip=jobs::localbox::tests::local_job_lifecycle"
    # does not see the job it just spawned as running in the darwin sandbox
    "--skip=jobs::localbox::tests::orphaned_job_probe_distinguishes_an_abandoned_launch_from_a_missing_pid"
  ];

  dontUseCargoParallelTests = true; # ETXTBSY: tests write+exec scripts

  nativeCheckInputs = [
    bash
    coreutils
    gawk
    git
    gnutar
    openssh
    procps
    # the ACP tests launch python3 fixture agents
    python3
  ];

  postInstall = ''
    # The guide lives at the source root; stage it to avoid copying the build tree.
    skillDir=$(mktemp -d)
    mkdir -p "$skillDir/openresearch-cli"
    cp SKILL.md "$skillDir/openresearch-cli/SKILL.md"
    installSkill "$skillDir/openresearch-cli"

    wrapProgram $out/bin/orx \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            bash
            coreutils
            git
            gnutar
            openssh
            procps
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [ xdg-utils ]
        )
      } \
      --set OPENRESEARCH_CLI_DISABLE_UPDATE 1 \
      --set ORX_NO_UPDATE_CHECK 1
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postInstallCheck = ''
    test -f $out/share/skills/openresearch/openresearch-cli/SKILL.md
    test "$(find "$out/share/skills/openresearch" -type f | wc -l)" -eq 1
  '';

  passthru = {
    category = "Workflow & Project Management";
    updater = mkUpdater {
      kind = "github-source";
      purl = "pkg:github/alphaXiv/OpenResearch";
      depHashKey = "cargoHash";
    };
  };

  meta = with lib; {
    description = "Local-first workspace for research agents and autoresearch";
    homepage = "https://openresearch.sh/";
    changelog = "https://github.com/alphaXiv/OpenResearch/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "orx";
    platforms = platforms.unix;
  };
})
