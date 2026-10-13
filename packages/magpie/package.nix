{
  lib,
  buildGoModule,
  fetchFromGitHub,
  stdenv,
  pkg-config,
  gtk3,
  webkitgtk_4_1,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  xdg-utils,
  coreutils,
  xcbuild,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule (finalAttrs: {
  pname = "magpie";
  version = "0.1.660";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wDJ7VEEm29JlO0tXdZaGTqu4p2e2dTU7vMXCr/VDNvQ=";
  };

  vendorHash = "sha256-XEaHZVw3co0yUV6fLUlSkvg9LlroKFj2B2sjMW1e6BU=";

  postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
    # os.Executable() is .magpie-wrapped, which lacks the GApps environment.
    substituteInPlace internal/autostart/autostart.go \
      --replace-fail 'exe, err := os.Executable()' 'exe, err := "'"$out"'/bin/magpie", error(nil)'
    # We ship the desktop entry for magpie:// links. One written to
    # ~/.local/share at startup would shadow it.
    rm internal/gui/scheme_linux.go
    substituteInPlace internal/gui/scheme_other.go \
      --replace-fail '!windows && !linux' '!windows'
  '';

  subPackages = [ "." ];
  tags = [ "production" ] ++ lib.optional stdenv.hostPlatform.isLinux "gtk3";
  ldflags = [
    "-s"
    "-w"
    "-X=main.version=v${finalAttrs.version}"
  ];

  preCheck = ''
    substituteInPlace internal/agent/cliupdate_test.go internal/library/rtk_upgrade_test.go \
      --replace-fail '/bin/cat' '${lib.getExe' coreutils "cat"}'
    substituteInPlace internal/library/rtk_test.go \
      --replace-fail '/bin/mkdir' '${lib.getExe' coreutils "mkdir"}'
    # The test narrows PATH to /usr/bin:/bin, which has no sleep in the sandbox.
    substituteInPlace internal/gui/providers_fetching_unix_test.go \
      --replace-fail 'sleep 4' '${lib.getExe' coreutils "sleep"} 4'
    # The source policy scan must not descend into buildGoModule's vendor/.
    substituteInPlace internal/proc/proc_test.go \
      --replace-fail 'd.Name() == "node_modules"' 'd.Name() == "node_modules" || d.Name() == "vendor"'
  '';
  # plutil
  nativeCheckInputs = lib.optionals stdenv.hostPlatform.isDarwin [ xcbuild ];
  # The default only tests subPackages, which has none of the logic.
  checkPhase = ''
    runHook preCheck
    go test -tags=${lib.concatStringsSep "," finalAttrs.tags} \
      ${lib.optionalString stdenv.hostPlatform.isDarwin "-skip='^TestAsAdmin$'"} ./...
    runHook postCheck
  '';

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    pkg-config
    wrapGAppsHook3
    copyDesktopItems
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gtk3
    webkitgtk_4_1
  ];

  desktopItems = lib.optionals stdenv.hostPlatform.isLinux [
    (makeDesktopItem {
      name = "magpie";
      desktopName = "magpie";
      comment = "One place to pick every AI agent's model";
      exec = "magpie %u";
      icon = "magpie";
      categories = [
        "Development"
        "Utility"
      ];
      mimeTypes = [ "x-scheme-handler/magpie" ];
    })
  ];

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ xdg-utils ]})
  '';

  postInstall =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      install -Dm644 internal/gui/icon-1024.png $out/share/icons/hicolor/1024x1024/apps/magpie.png
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      app="$out/Applications/magpie.app"
      mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
      mv "$out/bin/magpie" "$app/Contents/MacOS/magpie"
      ln -s "$app/Contents/MacOS/magpie" "$out/bin/magpie"
      cp build/darwin/magpie.icns build/darwin/Assets.car "$app/Contents/Resources/"
      substitute build/darwin/Info.plist "$app/Contents/Info.plist" \
        --replace-fail '@VERSION@' '${finalAttrs.version}'
    '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Utilities";

  meta = {
    description = "Manage AI agents' models, providers and subscriptions from one app";
    homepage = "https://github.com/yetone/magpie";
    changelog = "https://github.com/yetone/magpie/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ xyenon ];
    mainProgram = "magpie";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
