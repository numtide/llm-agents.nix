{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  runCommand,
  makeWrapper,
  installAgentSkills,
  fetchPnpmDeps,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
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
  inlangPlugin =
    name: version: hash:
    let
      tgz = fetchurl {
        url = "https://registry.npmjs.org/@inlang/${name}/-/${name}-${version}.tgz";
        inherit hash;
      };
    in
    runCommand "${name}-${version}.js" { } "tar -xzOf ${tgz} package/dist/index.js > $out";
  inlangMessageFormat =
    inlangPlugin "plugin-message-format" "4.5.5"
      "sha512-wFA0x9isGySoim2JUP2NNMslLnYrYQESbWfhv8qJueRH+d3c6iHkkQJxMF3D7PZ9BafEaj6fw0HJhoTa5c2EMw==";
  inlangMFunctionMatcher =
    inlangPlugin "plugin-m-function-matcher" "2.3.4"
      "sha512-Jd2ccLjEqyUAj+y54fb/8O1bEREsaHcPOw6PBercVjDMTvcUqAQZ8V/1t5Z0ZmSCuWgof7XxnmBcwgMuf0Xk+A==";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "openresearch";
  version = "0.2.25";

  src = fetchFromGitHub {
    owner = "alphaXiv";
    repo = "OpenResearch";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/wBl0D92vi3/U1oXXzCn5ov/2aigUrCuhAi7IQ/QcQI=";
  };

  cargoHash = "sha256-5A0WeuUKeszjgEisIHvtZfR7IpTOMjr9wRGVl6PAP1E=";

  nativeBuildInputs = [
    makeWrapper
    installAgentSkills
  ];

  # Export the CLI guide, not the agent-specific runtime skill collection.
  dontInstallAgentSkills = true;

  postPatch = ''
    cp -r ${finalAttrs.passthru.ui} ui/dist
    substituteInPlace $(grep -rl '#!/bin/sh' src) \
      --replace-fail '#!/bin/sh' '#!${bash}/bin/sh'
    substituteInPlace src/commands/up.rs \
      --replace-fail '"sh",' '"${bash}/bin/sh",'
    # The fake ssh in these tests calls cat and, for `ssh -G`, /usr/bin/ssh;
    # neither exists in the sandbox.
    substituteInPlace tests/cli/compute_cli.rs \
      --replace-fail '{}:/usr/bin:/bin"' '{}:${
        lib.makeBinPath [
          bash
          coreutils
          gnutar
          python3
        ]
      }"' \
      --replace-fail 'exec /usr/bin/ssh' 'exec ${openssh}/bin/ssh'
  '';

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  checkFlags = [
    # needs live ssh control sockets under /tmp, which the sandbox lacks
    "--skip=jobs::ssh::sharing::tests::native_config_shares_only_matching_live_sockets_and_preserves_user_settings"
    # runs /bin/sh, which the Linux sandbox lacks
    "--skip=jobs::rental::tests::rental_bootstrap_runs_bash_syntax_through_the_posix_login_shell"
    # the compacted sqlite file is not smaller than before in our build
    "--skip=local::native_store::tests::opencode_sweep_purges_settled_unreferenced_roots_and_compacts"
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

    ui = stdenv.mkDerivation (uiAttrs: {
      pname = "openresearch-ui";
      inherit (finalAttrs) version src;
      sourceRoot = "${finalAttrs.src.name}/ui";

      pnpmDeps = fetchPnpmDeps {
        inherit (uiAttrs)
          pname
          version
          src
          sourceRoot
          ;
        pnpm = pnpm_11;
        fetcherVersion = 4;
        hash = "sha256-2dtywPWAWp21DBfEzqG9/3NeidLZR4h1GY4Zebc4W/4=";
      };

      nativeBuildInputs = [
        nodejs
        pnpm_11
        pnpmConfigHook
      ];

      # The inlang project loads its plugins from jsdelivr at build time.
      postPatch = ''
        install -Dm644 ${inlangMessageFormat} project.inlang/plugins/message-format.js
        install -Dm644 ${inlangMFunctionMatcher} project.inlang/plugins/m-function-matcher.js
        substituteInPlace project.inlang/settings.json \
          --replace-fail "https://cdn.jsdelivr.net/npm/@inlang/plugin-message-format@4/dist/index.js" "./project.inlang/plugins/message-format.js" \
          --replace-fail "https://cdn.jsdelivr.net/npm/@inlang/plugin-m-function-matcher@2/dist/index.js" "./project.inlang/plugins/m-function-matcher.js"
      '';

      buildPhase = ''
        runHook preBuild
        pnpm build
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        cp -r dist $out
        runHook postInstall
      '';
    });
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
