{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGoModule rec {
  pname = "beads-viewer";
  version = "0.25.0";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "beads_viewer";
    tag = "v${version}";
    hash = "sha256-HckdaWMecY35XOQ1TTi/4fHwMXyl4n0QQK26oW4mMK8=";
  };

  vendorHash = null;

  # Remove go version constraint that requires newer Go than nixpkgs provides
  postPatch = ''
    sed -i '/^toolchain /d' go.mod
  '';

  subPackages = [ "cmd/bv" ];

  ldflags = [
    "-s"
    "-w"
    # Upstream resolves the exported Version in init() from the unexported
    # `version` variable, so inject there.
    "-X github.com/Dicklesworthstone/beads_viewer/pkg/version.version=v${version}"
  ];

  doCheck = false;

  doInstallCheck = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Graph-aware TUI for the Beads issue tracker";
    homepage = "https://github.com/Dicklesworthstone/beads_viewer";
    changelog = "https://github.com/Dicklesworthstone/beads_viewer/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ afterthought ];
    mainProgram = "bv";
    platforms = platforms.unix;
  };
}
