{
  lib,
  flake,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule rec {
  pname = "deja-vu";
  version = "0.23.4";

  src = fetchFromGitHub {
    owner = "vshulcz";
    repo = "deja-vu";
    tag = "v${version}";
    hash = "sha256-ODY1af7VfC2tNiWC5VCQupHpHzWac/1bHGRjwxzw/sI=";
  };

  # go.mod has no requirements and there is no go.sum.
  vendorHash = null;

  subPackages = [ "cmd/deja" ];

  # The suite takes about 25 minutes and drives git and real install targets.
  # Upstream CI runs it on every release. The version check below still runs.
  doCheck = false;

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd deja \
      --bash <($out/bin/deja completion bash) \
      --fish <($out/bin/deja completion fish) \
      --zsh <($out/bin/deja completion zsh)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Local search and recall over the session history coding agents already write to disk";
    longDescription = ''
      deja indexes the session files of Claude Code, Codex, Cursor, opencode,
      Gemini CLI and 38 other coding agents, including sessions from before it
      was installed, and recalls past decisions and fixes into the agent from
      the CLI, over MCP or through hooks. The index is local BM25, with no LLM
      and no embeddings.
    '';
    homepage = "https://github.com/vshulcz/deja-vu";
    changelog = "https://github.com/vshulcz/deja-vu/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ vshulcz ];
    mainProgram = "deja";
    platforms = platforms.unix;
  };
}
