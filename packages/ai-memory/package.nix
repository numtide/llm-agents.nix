{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  installShellFiles,
  cacert,
  makeBinaryWrapper,
  coreutils,
  curl,
  findutils,
  gawk,
  git,
  gnused,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  # Tools the POSIX hook scripts call; they run from agent configs with
  # whatever PATH the agent happens to have.
  hookPath = lib.makeBinPath [
    coreutils
    curl
    findutils
    gawk
    git
    gnused
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ai-memory";
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-memory";
    tag = "v${finalAttrs.version}";
    hash = "sha256-24uCvlPkbo8ldhTtzUAlswEGYDgIjvrEcZUZ5s/xg5c=";
  };

  cargoHash = "sha256-otRJTAhwyzSFN4s7+UkILZ7j/sSjerCvcfJ71DA9CDs=";

  cargoBuildFlags = [
    "--package"
    "ai-memory-cli"
  ];
  cargoTestFlags = finalAttrs.cargoBuildFlags ++ [
    "--bin"
    "ai-memory"
  ];

  # Expect "ai-memory" in current_exe(), the test binary is ai_memory-<hash>.
  checkFlags = map (t: "--skip=commands::install_hooks::tests::${t}") [
    "antigravity_apply_is_idempotent"
    "cursor_apply_is_idempotent"
    "kimi_code_apply_is_idempotent"
    "kimi_code_apply_preserves_providers_and_third_party_hooks"
  ];

  # build.rs would otherwise try to download the tailwind CLI for the web UI.
  env.TAILWIND_SKIP = "1";

  # `install-hooks`/`setup-agent` probe fixed FHS locations for the bundled
  # hook scripts; point the native-package candidate at our share/ dir.
  postPatch = ''
    substituteInPlace crates/ai-memory-cli/src/commands/{install_hooks,setup_agent}.rs \
      --replace-fail '"/usr/share/ai-memory/hooks/{sub}"' "\"$out/share/ai-memory/hooks/{sub}\""
    substituteInPlace crates/ai-memory-cli/src/commands/install_hooks.rs \
      --replace-fail '"/usr/share/ai-memory/hooks/claude-code"' "\"$out/share/ai-memory/hooks/claude-code\""
  '';

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  # reqwest loads native roots in the mcp_bridge test
  nativeCheckInputs = [ cacert ];

  postInstall = ''
    mkdir -p $out/share/ai-memory
    cp -r hooks $out/share/ai-memory/

    # Hook entry points are `#!/bin/sh` and locate _lib.sh via dirname before
    # anything else runs, so PATH has to be fixed up in the shebang line.
    for hook in $out/share/ai-memory/hooks/*/*.sh; do
      substituteInPlace "$hook" --replace-fail '#!/bin/sh' \
        '#!/bin/sh
    PATH=${hookPath}:$PATH'
    done

    installShellCompletion --cmd ai-memory \
      --bash <($out/bin/ai-memory completions bash) \
      --fish <($out/bin/ai-memory completions fish) \
      --zsh <($out/bin/ai-memory completions zsh)
  '';

  # git is shelled out to from several crates (wiki history, repo routing,
  # workstreams); wrap instead of patching every Command::new("git").
  postFixup = ''
    wrapProgram $out/bin/ai-memory --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = {
    description = "Long-term memory for AI coding agents";
    homepage = "https://github.com/akitaonrails/ai-memory";
    changelog = "https://github.com/akitaonrails/ai-memory/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "ai-memory";
    platforms = lib.platforms.unix;
  };
})
