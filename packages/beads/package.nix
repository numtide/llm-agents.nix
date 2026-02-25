{
  lib,
  buildGoModule,
  fetchFromGitHub,
  unpinGoModVersionHook,
  versionCheckHook,
}:

buildGoModule rec {
  pname = "beads";
  version = "0.56.1";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-hp+mKVCSzxxxUtOqspXuTbOJpeC8K9+UmmXSDr5Xa0k=";
  };

  vendorHash = "sha256-DlEnIVNLHWetwQxTmUNOAuDbHGZ9mmLdITwDdviphPs=";

  nativeBuildInputs = [ unpinGoModVersionHook ];

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  doInstallCheck = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "A distributed issue tracker designed for AI-supervised coding workflows";
    homepage = "https://github.com/steveyegge/beads";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ zimbatm ];
    mainProgram = "bd";
    platforms = platforms.unix;
  };
}
