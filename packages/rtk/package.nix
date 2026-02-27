{
  lib,
  fetchFromGitHub,
  rustPlatform,
  makeWrapper,
  jq,
  versionCheckHook,
  versionCheckHomeHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rtk";
  version = "0.22.2";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    tag = "v${finalAttrs.version}";
    hash = "sha256-dNODYk5PNiKU6+9AgB9c5f06PCcjStwFPEpuIb+BT0g=";
  };

  cargoHash = "sha256-lgmgorgT/KDSyzEcE33qkPF4f/3LJbAzEH0s9thTohE=";

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = true' 'lto = false' \
      --replace-fail 'codegen-units = 1' ""
  '';

  doCheck = false;

  postInstall = ''
    install -Dm755 $src/hooks/rtk-rewrite.sh $out/libexec/rtk/hooks/rtk-rewrite.sh
    wrapProgram $out/libexec/rtk/hooks/rtk-rewrite.sh \
      --prefix PATH : ${lib.makeBinPath [ jq ]}:$out/bin
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Utilities";

  meta = {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common developer commands";
    homepage = "https://github.com/rtk-ai/rtk";
    changelog = "https://github.com/rtk-ai/rtk/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "rtk";
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [ ryoppippi ];
  };
})
