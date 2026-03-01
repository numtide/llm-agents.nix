{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchCargoVendor,
  installShellFiles,
  rustPlatform,
  pkg-config,
  openssl,
  versionCheckHook,
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

let
  version = "0.6.74";

  src = fetchFromGitHub {
    owner = "just-every";
    repo = "code";
    tag = "v${version}";
    hash = "sha256-INMt4dd+ofHOmZW4umYSXuc/IfqQ+DZGwL2/r+wLLDE=";
  };
in
rustPlatform.buildRustPackage {
  pname = "code";
  inherit version src;

  cargoDeps = fetchCargoVendor {
    inherit src;
    sourceRoot = "source/code-rs";
    hash = "sha256-9V6N49CswKbIGyN9fAkJo7/DVzOdMj3xrDDMF0AqRMk=";
  };

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
    # Remove LTO to speed up builds
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "fat"' 'lto = false'
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
