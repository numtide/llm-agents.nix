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
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "plannotator";
    repo = "plannotator-tui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-I5Gc/YdpybsWvgYNELKLSRGszFJBiyg4C/MKAAQ8CPo=";
  };

  cargoHash = "sha256-umYlecdHYSr1Jzbi/0oI4ULRi5lf9O8kybtb5DeeWxo=";

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
