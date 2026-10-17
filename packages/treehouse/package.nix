{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
  installShellFiles,
  stdenv,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule rec {
  pname = "treehouse";
  version = "3.1.4";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "treehouse";
    tag = "v${version}";
    hash = "sha256-k4Wep5bIVXeLqQPJKrAAuQMvLtR/SdMaO3QZ2tp7aN4=";
  };

  vendorHash = "sha256-z8IndcHcZ6nLqhLtAYul3ppddpOA4AHGQWIlfYY/pfI=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${version}"
  ];

  nativeBuildInputs = [
    installShellFiles
  ];

  nativeCheckInputs = [ git ];

  # The default only tests subPackages, and the root package only has tests
  # for upstream's CI scripts. The skipped macOS tests need Apple's chmod +a.
  checkPhase = ''
    runHook preCheck
    go test -skip 'TestAllocationAndACLAttributes|TestShareSafeSkips/acl' \
      ./cmd/... ./internal/...
    runHook postCheck
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd treehouse \
      --bash <($out/bin/treehouse completion bash) \
      --fish <($out/bin/treehouse completion fish) \
      --zsh <($out/bin/treehouse completion zsh)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Reusable isolated worktree manager for AI agent sessions";
    homepage = "https://github.com/kunchenguid/treehouse";
    changelog = "https://github.com/kunchenguid/treehouse/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ azd325 ];
    mainProgram = "treehouse";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
