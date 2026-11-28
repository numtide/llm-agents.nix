{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  go-bin,
  libfido2,
  pkg-config,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule.override { go = go-bin; } rec {
  pname = "asc";
  version = "7.8.0";

  src = fetchFromGitHub {
    owner = "rorkai";
    repo = "App-Store-Connect-CLI";
    tag = version;
    hash = "sha256-q9kAlt0+77ERM223WfwhSwSKCrCU21RergDE/ShOSNI=";
  };

  vendorHash = "sha256-OS0oygHuYa6n9vRkvo9IP6IuXHyZske+yH3nUA5ee48=";

  subPackages = [ "." ];

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ pkg-config ];
  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ libfido2 ];

  tags = lib.optionals stdenv.hostPlatform.isDarwin [ "fido2" ];

  env.CGO_ENABLED = if stdenv.hostPlatform.isDarwin then "1" else "0";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  postInstall = ''
    mv $out/bin/App-Store-Connect-CLI $out/bin/asc
  '';

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Fast, scriptable CLI for the App Store Connect API";
    homepage = "https://github.com/rorkai/App-Store-Connect-CLI";
    changelog = "https://github.com/rorkai/App-Store-Connect-CLI/releases/tag/${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ ryoppippi ];
    mainProgram = "asc";
    platforms = platforms.unix;
  };
}
