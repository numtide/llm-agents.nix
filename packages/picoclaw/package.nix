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
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "sipeed";
    repo = "picoclaw";
    tag = "v${version}";
    hash = "sha256-zCeURNN152yL3Qi1UFDvSB85xflbLAMzQUTwGThALss=";
  };

  vendorHash = "sha256-EJAYrVMDgAXssqRcCdjrYbuKsKSp7tIG5xvLeY0xZeY=";

  nativeBuildInputs = [ unpinGoModVersionHook ];

  postPatch = ''
    # go:embed in cmd/picoclaw/internal/onboard/command.go expects a workspace
    # directory copied there by go:generate which doesn't run during nix builds
    cp -r workspace cmd/picoclaw/internal/onboard/workspace
  '';

  subPackages = [ "cmd/picoclaw" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/sipeed/picoclaw/cmd/picoclaw/internal.version=${version}"
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
