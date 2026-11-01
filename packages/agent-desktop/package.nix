{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installAgentSkills,
  versionCheckHook,
  xcbuild,
  zlib,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agent-desktop";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-desktop";
    tag = "v${finalAttrs.version}";
    hash = "sha256-0r5bO5oQonq/B/gQYHrjdrQFVfyK3gAZudbaTVe89v0=";
  };

  cargoHash = "sha256-PYZ+PID4Kl3hckTf5RzPXl9JIr+P4lA7Tu2vXXfQ6QM=";

  nativeBuildInputs = [
    installAgentSkills
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    # crates/macos/build.rs compiles its Objective-C bridges with
    # `xcrun --sdk macosx clang`; xcbuild answers with the nixpkgs SDK.
    xcbuild
  ];

  # The macOS crate links ImageIO, which pulls in libz.
  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ zlib ];

  # The CLI spawns a platform helper that must sit beside it as a regular
  # file (the macOS clipboard helper, the Linux clipboard owner). Build the
  # helper crate's binaries together with the CLI so both land in $out/bin.
  cargoBuildFlags = [
    "--package"
    "agent-desktop"
    "--package"
    (if stdenv.hostPlatform.isDarwin then "agent-desktop-macos" else "agent-desktop-linux")
    "--bins"
  ];

  # Upstream targets macOS 10.15, where NSWorkspace fullPathForApplication:
  # is not yet deprecated. The nixpkgs SDK cannot go below 11.0 on arm64,
  # so with -Werror the deprecation warning fails the build.
  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace crates/macos/build.rs \
      --replace-fail '"-Werror",' '"-Werror", "-Wno-error=deprecated-declarations",'
  '';

  # The suites drive the live accessibility bus/session of the host.
  doCheck = false;

  # The source also carries skills for the FFI library, the other platforms
  # and the separate JEV helper; ship only what this binary serves.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/agent-desktop
    installSkill skills/agent-desktop-${if stdenv.hostPlatform.isDarwin then "macos" else "linux"}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru.category = "Utilities";

  meta = {
    description = "Computer use for AI agents through the OS accessibility tree";
    homepage = "https://github.com/vercel-labs/agent-desktop";
    changelog = "https://github.com/vercel-labs/agent-desktop/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ ryoppippi ];
    mainProgram = "agent-desktop";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
