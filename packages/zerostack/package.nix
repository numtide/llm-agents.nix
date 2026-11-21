{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  aws-lc,
  gitMinimal,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "zerostack";
  version = "1.8.6";

  src = fetchFromGitHub {
    owner = "gi-dellav";
    repo = "zerostack";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lexZZHDAMsaRyoaa7ptxMUWNZmj/1Mv8apMhbBep6zU=";
  };

  cargoHash = "sha256-szlDZa4Z9tG+YQWpwcAmjtZSo96ss7nBOLN8nZTb7no=";

  # .cargo/config.toml forces mold as the linker on x86_64-linux; use the
  # stdenv linker instead.
  postPatch = ''
    rm .cargo/config.toml
  '';

  # nixpkgs' cargo setup hook exports AWS_LC_SYS_USE_SYSTEM=1, so aws-lc-sys
  # (rustls crypto provider) links against the system aws-lc found through
  # pkg-config instead of building its vendored copy.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ aws-lc ];

  # Same feature set as upstream's own Nix package.
  buildFeatures = [
    "acp"
    "memory"
    "multithread"
  ];

  # Worktree/session tests shell out to git.
  nativeCheckInputs = [ gitMinimal ];

  # buildRustPackage exports RUST_LOG="", which EnvFilter::try_from_default_env
  # accepts as an empty filter, breaking the default "warn" filter test.
  preCheck = ''
    unset RUST_LOG
  '';

  checkFlags = [
    # Expects CARGO_MANIFEST_DIR to be a git checkout; the source is a tarball.
    "--skip=tests::session_tests::detect_git_branch_in_repo_returns_nonempty"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Minimalistic coding agent optimized for memory footprint and performance";
    homepage = "https://github.com/gi-dellav/zerostack";
    changelog = "https://github.com/gi-dellav/zerostack/releases/tag/v${finalAttrs.version}";
    license = licenses.gpl3Only;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ chansuke ];
    mainProgram = "zerostack";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
