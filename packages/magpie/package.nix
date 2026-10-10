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

  # Keep desktop links and autostart on the GApp wrapper, not the inner binary.
  patches = lib.optionals stdenv.hostPlatform.isLinux [
    ./linux-launcher.patch
  ];
  postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
    substituteInPlace internal/autostart/autostart.go internal/autostart/launcher_linux_test.go \
      --replace-fail '@magpie@' "$out/bin/magpie"
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
    # Only exclude dependencies added by buildGoModule from the source policy scan.
    substituteInPlace internal/proc/proc_test.go \
      --replace-fail 'd.Name() == "node_modules"' 'd.Name() == "node_modules" || d.Name() == "vendor"'
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Keep script generation and cancellation assertions even without osascript.
    substituteInPlace internal/update/admin_test.go \
      --replace-fail '// AppleScript unescapes it back to the script' \
        'if _, err := exec.LookPath("osascript"); err != nil {
          t.Skip("AppleScript interpreter is unavailable in the build sandbox")
        }
        // AppleScript unescapes it back to the script'
  '';
  nativeCheckInputs = lib.optionals stdenv.hostPlatform.isDarwin [ xcbuild ];
  checkPhase = ''
    runHook preCheck
    go test -tags=${lib.concatStringsSep "," finalAttrs.tags} ./...
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
