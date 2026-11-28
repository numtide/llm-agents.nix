{
  lib,
  flake,
  rustPlatform,
  fetchCrate,
  git,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tilth";
  version = "0.15.0";

  # The GitHub repository is gone, crates.io still has the releases.
  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-YIJm9QG0Sm6TZKgd8j9ydKJ4vIcWP90pfDYZaww/s0U=";
  };

  cargoHash = "sha256-H2Ho7gOfTC9Ogv0QgbeRRO3+OoTYqT4I/71mSQ/LQAw=";

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];
  # Lints source files that the crate tarball does not ship.
  checkFlags = [ "--skip=only_the_runner_starts_git" ];

  postInstall = ''
    wrapProgram $out/bin/tilth --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Tree-sitter-powered code reading CLI and MCP server for AI agents";
    homepage = "https://crates.io/crates/tilth";
    changelog = "https://crates.io/crates/tilth/${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "tilth";
    platforms = platforms.unix;
  };
})
