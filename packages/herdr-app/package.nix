{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  buildPackages,
  pkg-config,
  makeWrapper,
  clang,
  fontconfig,
  freetype,
  libxkbcommon,
  libxcb,
  wayland,
  vulkan-loader,
}:
let
  pname = "herdr-app";
  version = "0.1.9";

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr-app";
    tag = "v${version}";
    # vendor/ghostty is a git submodule (ghostty-org/ghostty).
    fetchSubmodules = true;
    # Verified with `nix-prefetch-git --fetch-submodules`.
    hash = "sha256-XXAcJWwaaec/E941NkGAiCWgeHyT5jpYKcfz+8mbkvI=";
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  inherit pname version src;

  __structuredAttrs = true;

  cargoHash = "sha256-NOLcdtc9zLojjkEwGbjiTGTxDhX9w42hWtNrrE3kID4=";

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
    wrapProgram $out/bin/herdr-app --set-default HERDR_TELEMETRY 0
  '';

  passthru.category = "Desktop Apps";

  meta = with lib; {
    description = "Herdr desktop app for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    changelog = "https://github.com/herdrdev/herdr-app/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = [ ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "herdr-app";
  };
})
