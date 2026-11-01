{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  rustPlatform,
  zig_0_16,
  installAgentSkills,
  xcbuild,
  cctools,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr-core";
  version = "0.1.16";

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr-core";
    tag = "v${finalAttrs.version}";
    # vendor/ghostty is a git submodule (ghostty-org/ghostty).
    fetchSubmodules = true;
    hash = "sha256-TIOXZswCum0g3qcDK+RDZb9Y7lUu+bx+Oyja4EtKKh4=";
  };

  cargoHash = "sha256-hMkych62liZ+Oe5huM2drN5/6ckpF8AEHH2dyskcivo=";

  zigDeps = zig_0_16.fetchDeps {
    inherit (finalAttrs) pname version;
    src = "${finalAttrs.src}/vendor/ghostty";
    fetchAll = true;
    hash = "sha256-G9xbZ/pyQTDIfzG0h++i70a45zpwyYpZMBZfAnoOQw0=";
  };

  nativeBuildInputs = [
    zig_0_16
    installAgentSkills
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    # zig's macOS SDK detection shells out to xcode-select/xcrun.
    xcbuild
    # libghostty-vt's CombineArchivesStep runs `libtool` on Darwin.
    cctools
  ];

  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigConfigure = true;
  dontUseZigInstall = true;

  # xcbuild's xcodebuild stub makes ghostty enable the unneeded xcframework,
  # which it cannot create. Tools with absolute paths are absent in the sandbox.
  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace crates/ghostty-vt/build.rs \
      --replace-fail '"-Demit-lib-vt",' '"-Demit-lib-vt", "-Demit-xcframework=false",'
    substituteInPlace vendor/ghostty/pkg/apple-sdk/native_link.zig \
      --replace-fail '"/usr/bin/xcrun"' '"xcrun"'
    substituteInPlace vendor/ghostty/src/build/GhosttyLibVt.zig \
      --replace-fail '"/bin/ln"' '"ln"'
    substituteInPlace vendor/ghostty/src/build/LibtoolStep.zig \
      --replace-fail '/bin/cp ' 'cp ' \
      --replace-fail '/usr/bin/ranlib ' 'ranlib '
  '';

  preBuild = ''
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    cp -rL ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  # Tests spawn PTYs and a long-running core, which the sandbox does not allow.
  doCheck = false;

  dontInstallAgentSkills = true;

  # Upstream's installer adds this name; docs and agent skills use it.
  postInstall = ''
    ln -s herdr-core $out/bin/hc
    installSkill skills/herdr-core
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postInstallCheck = ''
    test -f "$out/share/skills/herdr-core/herdr-core/SKILL.md"
  '';

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Terminals for coding agents that keep running";
    homepage = "https://github.com/herdrdev/herdr-core";
    changelog = "https://github.com/herdrdev/herdr-core/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    maintainers = with flake.lib.maintainers; [ mulatta ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "hc";
  };
})
