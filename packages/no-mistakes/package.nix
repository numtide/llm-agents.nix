{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  stdenv,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule rec {
  pname = "no-mistakes";
  version = "1.106.1";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    tag = "v${version}";
    hash = "sha256-pD4i6jZO0ltr3mdm91zkm2aCbQ9mzsbWz5CzhEI4SKU=";
  };

  vendorHash = "sha256-maAVBptEtdrGanJHwAPAmuGBorzIMUgK6T+NmIz1kS0=";

  subPackages = [ "cmd/no-mistakes" ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v${version}"
  ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd no-mistakes \
      --bash <($out/bin/no-mistakes completion bash) \
      --fish <($out/bin/no-mistakes completion fish) \
      --zsh <($out/bin/no-mistakes completion zsh)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Agent-driven Git push gate and validation pipeline";
    homepage = "https://github.com/kunchenguid/no-mistakes";
    changelog = "https://github.com/kunchenguid/no-mistakes/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ azd325 ];
    mainProgram = "no-mistakes";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
