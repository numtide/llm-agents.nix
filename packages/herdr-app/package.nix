{
  lib,
  stdenv,
  flake,
  rustPlatform,
  fetchFromGitHub,
  buildPackages,
  pkg-config,
  makeWrapper,
  clang,
  xcbuild,
  cctools,
  fontconfig,
  freetype,
  libxkbcommon,
  libxcb,
  wayland,
  vulkan-loader,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr-app";
  version = "0.1.11";

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr-app";
    tag = "v${finalAttrs.version}";
    # vendor/ghostty is a git submodule (ghostty-org/ghostty).
    fetchSubmodules = true;
    hash = "sha256-vuY2a3iGVJ8+oOXnQbWY5/hYNUdCov5yDuttCq9swr4=";
  };

  __structuredAttrs = true;

  cargoHash = "sha256-DX4+ELg1vtprKv8N6R8rW42wty+hKMo96/MxiiUmqu8=";

  # Build-platform Zig: passthru attrs are not spliced.
  zigDeps = buildPackages.zig_0_16.fetchDeps {
    inherit (finalAttrs) pname version;
    src = "${finalAttrs.src}/vendor/ghostty";
    fetchAll = true;
    hash = "sha256-G9xbZ/pyQTDIfzG0h++i70a45zpwyYpZMBZfAnoOQw0=";
  };

  nativeBuildInputs = [
    buildPackages.zig_0_16.hook
    rustPlatform.bindgenHook
    # ghostty-sys falls back to Zig's builtin headers when clang is not on
    # PATH, and those break the libc headers that bindgenHook adds.
    clang
    pkg-config
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    # zig's macOS SDK detection shells out to xcode-select/xcrun.
    xcbuild
    # libghostty-vt's CombineArchivesStep runs `libtool` on Darwin.
    cctools
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    fontconfig
    freetype
    libxkbcommon
    libxcb
    wayland
  ];

  # Without HERDR_APP_RELEASE at build time the app never updates itself and
  # has no telemetry endpoint.
  doCheck = false;

  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigInstall = true;

  # xcbuild's xcodebuild stub makes ghostty enable the unneeded xcframework,
  # which it cannot create. Tools with absolute paths are absent in the sandbox.
  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace crates/ghostty-sys/build.rs \
      --replace-fail '"-Demit-lib-vt",' '"-Demit-lib-vt", "-Demit-xcframework=false",'
    substituteInPlace vendor/ghostty/pkg/apple-sdk/native_link.zig \
      --replace-fail '"/usr/bin/xcrun"' '"xcrun"'
    substituteInPlace vendor/ghostty/src/build/GhosttyLibVt.zig \
      --replace-fail '"/bin/ln"' '"ln"'
    substituteInPlace vendor/ghostty/src/build/LibtoolStep.zig \
      --replace-fail '/bin/cp ' 'cp ' \
      --replace-fail '/usr/bin/ranlib ' 'ranlib '
  '';

  postConfigure = ''
    export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
    cp -rL ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm444 assets/icons/herdr-ui-icon-clean.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
    install -Dm444 /dev/stdin $out/share/applications/herdr-app.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Herdr
    Comment=Terminals and coding agents that keep running
    Exec=herdr-app
    Icon=herdr-app
    Terminal=false
    Categories=Development;
    StartupWMClass=herdr-app
    EOF
  '';

  # GPUI loads Vulkan and Wayland at run time.
  postFixup = ''
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      patchelf $out/bin/herdr-app --add-rpath ${
        lib.makeLibraryPath [
          vulkan-loader
          wayland
          libxkbcommon
        ]
      }
    ''}
  '';

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Herdr desktop app for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    changelog = "https://github.com/herdrdev/herdr-app/releases/tag/v${finalAttrs.version}";
    license = licenses.asl20;
    maintainers = with flake.lib.maintainers; [ arthurk ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "herdr-app";
  };
})
