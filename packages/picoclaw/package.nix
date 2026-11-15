{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  unpinGoModVersionHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule rec {
  pname = "picoclaw";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "afjcjsbx";
    repo = "picoclaw";
    tag = "v${version}";
    hash = "sha256-Y+OWgcXXfHYdiwmZmebUbXSH6ZBhfQNy2LGwoZCb/bY=";
  };

  vendorHash = "sha256-gSLL2lt3ynSKIwNFUInC/qgpfNxs1IMImnxUTsQVi6I=";

  nativeBuildInputs = [ unpinGoModVersionHook ];

  # goolm is the pure-Go Matrix crypto backend, so libolm is not linked.
  env.CGO_ENABLED = "0";
  tags = [
    "goolm"
    "stdjson"
  ];

  subPackages = [ "cmd/picoclaw" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/sipeed/picoclaw/pkg/config.Version=${version}"
  ];

  # Tests require runtime configuration and network access
  doCheck = false;

  doInstallCheck = true;
  versionCheckProgramArg = "version";
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Tiny, fast, and deployable anywhere — automate the mundane, unleash your creativity";
    homepage = "https://afjcjsbx.github.io/picoclaw/";
    changelog = "https://github.com/afjcjsbx/picoclaw/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ afjcjsbx ];
    mainProgram = "picoclaw";
    platforms = lib.platforms.unix;
  };
}
