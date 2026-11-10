{
  lib,
  stdenv,
  flake,
  rustPlatform,
  fetchFromGitHub,
  buildPackages,
  pkg-config,
  makeWrapper,
  makeBinaryWrapper,
  clang,
  xcbuild,
  cctools,
  herdr-core,
  fontconfig,
  freetype,
  libxkbcommon,
  libxcb,
  wayland,
  vulkan-loader,
  zstd,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr-app";
  version = "0.1.14";

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr-app";
    tag = "v${finalAttrs.version}";
    # vendor/ghostty is a git submodule (ghostty-org/ghostty).
    fetchSubmodules = true;
    hash = "sha256-vVwLuzaeJXfBrWw/pM4ZEntSeBDaKRFijWcyORBAoxw=";
  };

  __structuredAttrs = true;

  cargoHash = "sha256-X+Bh3iagth4glCWo3/8979zTWfhacGXOotpF4ruAeYg=";

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
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ makeWrapper ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    # A shell script cannot be a bundle's main executable.
    makeBinaryWrapper
    # zig's macOS SDK detection shells out to xcode-select/xcrun; also
    # provides PlistBuddy for checking the bundle's Info.plist.
    xcbuild
    # libghostty-vt's CombineArchivesStep runs `libtool` on Darwin.
    cctools
  ];

  buildInputs = [
    zstd
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    fontconfig
    freetype
    libxkbcommon
    libxcb
    wayland
  ];

  env.ZSTD_SYS_USE_PKG_CONFIG = "1";

  # Without HERDR_APP_RELEASE at build time the app never updates itself and
  # has no telemetry endpoint.
  doCheck = false;

  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigInstall = true;

  # Tools with absolute paths are absent in the sandbox.
  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
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

  postInstall =
    lib.optionalString stdenv.hostPlatform.isDarwin ''
      app=$out/Applications/Herdr.app
      plist=$app/Contents/Info.plist
      mkdir -p $app/Contents/MacOS
      mv $out/bin/herdr-app $app/Contents/MacOS/Herdr
      install -Dm444 -t $app/Contents/Resources assets/icons/Herdr.icns LICENSE THIRD-PARTY-NOTICES

      # Reuse upstream's plist so permission strings and bundle id don't drift.
      sed -n '/<<PLIST$/,/^PLIST$/{//!p}' scripts/package \
        | sed 's/\$version/${finalAttrs.version}/g' > $plist

      # sed exits 0 when nothing matches; parse the result and fail on drift.
      check() {
        local got
        got=$(PlistBuddy -c "Print :$1" $plist)
        # xcbuild's PlistBuddy, unlike Apple's, quotes strings with punctuation.
        got=''${got#\"}
        got=''${got%\"}
        [[ $got == "$2" ]] || { echo "Info.plist $1: got '$got', want '$2'" >&2; exit 1; }
      }
      check CFBundleExecutable Herdr
      check CFBundleIdentifier dev.herdr.app
      check CFBundleIconFile Herdr
      check CFBundleShortVersionString ${finalAttrs.version}
      check CFBundleVersion ${finalAttrs.version}
      if grep -q '\$' $plist; then
        echo "Info.plist has unexpanded shell variables" >&2
        exit 1
      fi

      ln -sf ../Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
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

    # Suffix: a core the user installed wins, since a newer one of the same
    # generation only adds. Without any, the app would `curl | sh` one.
    # On Darwin the wrapper sits inside the bundle so Dock/Finder launches
    # get it too, and the real binary's `.Herdr-wrapped` name keeps the app
    # from linking ~/.local/bin/herdr-app to a store path that GC can remove.
    wrapProgram ${
      if stdenv.hostPlatform.isDarwin then
        "$out/Applications/Herdr.app/Contents/MacOS/Herdr"
      else
        "$out/bin/herdr-app"
    } --suffix PATH : ${lib.makeBinPath [ herdr-core ]}
  '';

  doInstallCheck = stdenv.hostPlatform.isDarwin;
  installCheckPhase = ''
    runHook preInstallCheck
    app=$out/Applications/Herdr.app
    test -x $app/Contents/MacOS/Herdr
    test -x $app/Contents/MacOS/.Herdr-wrapped
    test -x $out/bin/herdr-app
    test -s $app/Contents/Resources/Herdr.icns
    runHook postInstallCheck
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
