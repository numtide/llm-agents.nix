{
  lib,
  flake,
  bash,
  buildGoModule,
  go_1_26,
  fetchFromGitHub,
  git,
  versionCheckHook,
  versionCheckHomeHook,
}:

# crit requires a go >= 1.26 toolchain.
(buildGoModule.override { go = go_1_26; }) rec {
  pname = "crit";
  version = "0.23.1";

  src = fetchFromGitHub {
    owner = "tomasz-tomczyk";
    repo = "crit";
    tag = "v${version}";
    hash = "sha256-g0pjb/Qd8W4og13XaXE7j5IxFqMnXMJiYe6Z0BJnMfU=";
  };

  vendorHash = "sha256-WUTBKcMEnOnMnHsABjP2iKr1pNJcHfG7RNw7cBx0Hl4=";

  subPackages = [ "cmd/crit" ];

  # Story-generation tests exec fake agent scripts via /usr/bin/env, which is
  # absent from the sandbox.
  postPatch = ''
    substituteInPlace cmd/crit/cli_handlers_story_llm_test.go \
      --replace-fail '#!/usr/bin/env bash' '#!${lib.getExe bash}'
  '';

  # Preflight tests shell out to `git init`.
  nativeCheckInputs = [ git ];
  preCheck = ''
    export HOME=$(mktemp -d)
    git config --global user.email crit@example.com
    git config --global user.name crit
    git config --global init.defaultBranch main
  '';

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Local-first review tool for coding-agent plans, diffs, and web pages";
    homepage = "https://github.com/tomasz-tomczyk/crit";
    changelog = "https://github.com/tomasz-tomczyk/crit/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ ahacop ];
    mainProgram = "crit";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
