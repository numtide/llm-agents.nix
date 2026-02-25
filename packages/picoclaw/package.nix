{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  go_1_25,
  unpinGoModVersionHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule.override { go = go_1_25; } rec {
  pname = "picoclaw";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "sipeed";
    repo = "picoclaw";
    tag = "v${version}";
    hash = "sha256-2q/BQmZaSh88kwquiQlWGS36MVFWWdUzsMxGp4cAMiE=";
  };

  vendorHash = "sha256-3kDU3pbcz+2cd36/bcbdU/IXTAeJosBZ+syUQqO2bls=";

  nativeBuildInputs = [ unpinGoModVersionHook ];

  postPatch = ''
    # go:embed in cmd_onboard.go expects a workspace directory copied by go:generate
    cp -r workspace cmd/picoclaw/workspace
  '';

  subPackages = [ "cmd/picoclaw" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  # Tests require runtime configuration and network access
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Tiny, fast, and deployable anywhere — automate the mundane, unleash your creativity";
    homepage = "https://picoclaw.io";
    changelog = "https://github.com/sipeed/picoclaw/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ commandodev ];
    mainProgram = "picoclaw";
    platforms = lib.platforms.unix;
  };
}
