{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  sqlite,
  versionCheckHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "plannotator-tui";
  version = "0.9.9";

  src = fetchFromGitHub {
    owner = "plannotator";
    repo = "plannotator-tui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-z34MwdUBwjXBaF/gw+aNAMMzwSI2yn0Z8UWu19YTkk0=";
  };

  cargoHash = "sha256-wcgVVU9zhWhf2nPYvJbddkydiQpBA00gejHu/i9fZaU=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ sqlite ];

  env.LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";

  # The darwin cc-wrapper re-quotes non-ASCII arguments as $'\303\274', which
  # breaks linking the fake herdr in a temp dir named with "ü".
  postPatch = ''
    substituteInPlace crates/plannotator-tui/tests/terminal.rs \
      --replace-fail ' ü-' ' u-'
  '';

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Code Review";

  meta = {
    description = "Annotate Markdown in the terminal and send feedback to coding agents";
    homepage = "https://github.com/plannotator/plannotator-tui";
    changelog = "https://github.com/plannotator/plannotator-tui/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = [ lib.maintainers.ramblurr ];
    mainProgram = "plannotator-tui";
    platforms = lib.platforms.unix;
  };
})
