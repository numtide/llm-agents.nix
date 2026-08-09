{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  rustPlatform,
  pkg-config,
  openssl,
  versionCheckHook,
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

let
  version = "0.6.170";

  src = fetchFromGitHub {
    owner = "just-every";
    repo = "code";
    tag = "v${version}";
    hash = "sha256-ZXIr7RQWFG+xNB01m8obMhcQzZfJrueUgM74c6HTbgE=";
  };
in
rustPlatform.buildRustPackage {
  pname = "code";
  inherit version src;

  cargoHash = "sha256-PRiXU6ZPruHpIBNEg9FmYPOWuMpMal7W8ChfTBgXztQ=";

  sourceRoot = "source/code-rs";

  cargoBuildFlags = [
    "--bin"
    "code"
    "--bin"
    "code-tui"
    "--bin"
    "code-exec"
  ];

  nativeBuildInputs = [
    installShellFiles
    pkg-config
  ];

  buildInputs = [ openssl ];

  env.CODE_VERSION = version;

  preBuild = ''
    # Remove LTO and single codegen-unit to reduce peak memory usage.
    # The code-tui crate has a 42k-line source file (chatwidget.rs) that
    # causes the compiler to OOM on aarch64-linux with codegen-units=1.
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "fat"' 'lto = false' \
      --replace-fail 'codegen-units = 1' 'codegen-units = 16'
  '';

  doCheck = false;

  postInstall = ''
    # Add coder as an alias to avoid conflict with vscode
    ln -s code $out/bin/coder
  ''
  + lib.optionalString installShellCompletions ''
    installShellCompletion --cmd code \
      --bash <($out/bin/code completion bash) \
      --fish <($out/bin/code completion fish) \
      --zsh <($out/bin/code completion zsh)
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Fork of codex. Orchestrate agents from OpenAI, Claude, Gemini or any provider.";
    homepage = "https://github.com/just-every/code/";
    changelog = "https://github.com/just-every/code/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "code";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
  };
}
