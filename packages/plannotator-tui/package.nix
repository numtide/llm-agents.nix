{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  git,
  sqlite,
  versionCheckHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "plannotator-tui";
  version = "0.12.1";

  src = fetchFromGitHub {
    owner = "plannotator";
    repo = "plannotator-tui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zmsK85oS07IQUEV5avjSmdZO2ZmqOQMF/CmchyRHV1M=";
  };

  cargoHash = "sha256-mN/um6aG283uG4Ve/rWnHZ2kktfWWWlXYUr/A0N774c=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ sqlite ];

  nativeCheckInputs = [ git ];

  env.LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";

  # diffs-rs needs libgit2-sys' vendored source and refuses LIBGIT2_NO_VENDOR
  dontCargoUseSystemLibs = true;

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
