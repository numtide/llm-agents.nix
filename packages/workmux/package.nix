{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installAgentSkills,
  installShellFiles,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "workmux";
  version = "0.1.278";

  src = fetchFromGitHub {
    owner = "raine";
    repo = "workmux";
    tag = "v${version}";
    hash = "sha256-DJn1cpSL/P4InQuU+oEusf68nezA1NgBBsGu4XujQEM=";
  };

  cargoHash = "sha256-v3wBUyV6no5t7wSXEjlfZ2hga/Qdyogzr7F4AV1V/gs=";

  nativeBuildInputs = [
    installAgentSkills
    installShellFiles
  ];

  # Some tests require filesystem access outside the sandbox
  doCheck = false;

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    export HOME=$(mktemp -d)
    installShellCompletion --cmd workmux \
      --bash <($out/bin/workmux completions bash) \
      --fish <($out/bin/workmux completions fish) \
      --zsh <($out/bin/workmux completions zsh)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Git worktrees + tmux windows for zero-friction parallel dev";
    homepage = "https://github.com/raine/workmux";
    changelog = "https://github.com/raine/workmux/blob/v${version}/CHANGELOG.md";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "workmux";
    platforms = platforms.all;
  };
}
