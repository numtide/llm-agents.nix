{
  lib,
  stdenv,
  darwin,
  flake,
  buildNpmPackage,
  electron_44,
  hermes-agent,
  makeWrapper,
  xcbuild,
  copyDesktopItems,
  makeDesktopItem,
  git,
  openssh,
  ripgrep,
  gh,
  curl,
  file,
  xprop,
  xdg-utils,
  gdk-pixbuf,
}:

let
  # Must match the major version upstream pins; node-pty is rebuilt against it.
  electron = electron_44;

  isLinux = stdenv.hostPlatform.isLinux;
  isDarwin = stdenv.hostPlatform.isDarwin;

  targetPlatform =
    if isLinux then
      "linux"
    else if isDarwin then
      "darwin"
    else
      throw "hermes-desktop: unsupported host platform ${stdenv.hostPlatform.system}";

  targetArch =
    if stdenv.hostPlatform.isAarch64 then
      "arm64"
    else if stdenv.hostPlatform.isx86_64 then
      "x64"
    else
      throw "hermes-desktop: unsupported host architecture ${stdenv.hostPlatform.system}";

  runtimeTools = [
    git
    openssh
    ripgrep
    gh
    curl
  ]
  ++ lib.optionals isLinux [
    xprop
    xdg-utils
  ];

  runtimePath = lib.makeBinPath runtimeTools;
  hermesExecutable = lib.getExe hermes-agent;
in
buildNpmPackage {
  pname = "hermes-desktop";
  inherit (hermes-agent) version src;

  # Desktop, TUI and web share one root package-lock.json. Reuse the FOD that
  # hermes-agent's frontend already fetched rather than storing the same npm
  # graph under a second hash.
  npmDeps = hermes-agent.hermes-frontend.npmDeps;
  # Upstream .npmrc sets engine-strict and pins a bleeding-edge Node that
  # nixpkgs does not cache; the offline install works fine with default nodejs.
  npmFlags = [ "--engine-strict=false" ];

  # npmConfigHook already installs with --ignore-scripts. Keep its automatic
  # rebuild inert too: node-pty must be compiled manually for Electron's ABI,
  # not the build Node ABI, and Electron must never download a binary.
  npmRebuildFlags = [ "--ignore-scripts" ];
  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  dontNpmBuild = true;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals isLinux [
    copyDesktopItems
    # gdk-pixbuf-thumbnailer, already in the build closure via electron
    gdk-pixbuf
  ]
  ++ lib.optionals isDarwin [
    file
    xcbuild
    darwin.autoSignDarwinBinariesHook
  ];

  buildPhase = ''
    runHook preBuild

    upstream_electron_manifest=$(node -p "require('./apps/desktop/package.json').devDependencies.electron")
    upstream_electron_lock=$(node -p "(p => (p['apps/desktop/node_modules/electron'] ?? p['node_modules/electron']).version)(require('./package-lock.json').packages)")
    if [[ "''${upstream_electron_manifest%%.*}" != ${lib.versions.major electron.version} || "''${upstream_electron_lock%%.*}" != ${lib.versions.major electron.version} ]]; then
      echo "error: upstream Electron major differs from electron_${lib.versions.major electron.version}" >&2
      echo "manifest=$upstream_electron_manifest lock=$upstream_electron_lock" >&2
      echo "Re-check Electron compatibility and update this package deliberately." >&2
      exit 1
    fi

    upstream_node_pty_manifest=$(node -p "require('./apps/desktop/package.json').dependencies['node-pty']")
    upstream_node_pty_lock=$(node -p "require('./package-lock.json').packages['node_modules/node-pty'].version")
    if [[ "$upstream_node_pty_manifest" != 1.1.0 || "$upstream_node_pty_lock" != 1.1.0 ]]; then
      echo "error: upstream node-pty pins changed from the reviewed 1.1.0" >&2
      echo "manifest=$upstream_node_pty_manifest lock=$upstream_node_pty_lock" >&2
      echo "Re-check native staging and Electron ABI compatibility." >&2
      exit 1
    fi

    mkdir -p apps/desktop/build

    pushd apps/desktop

    # Published prebuilds target other Node/Electron ABIs and are not usable on
    # NixOS. Force a native build using the headers for the Electron derivation
    # that the launcher below actually executes.
    rm -rf ../../node_modules/node-pty/build ../../node_modules/node-pty/prebuilds
    export npm_config_nodedir=${electron.headers}
    export npm_config_runtime=electron
    export npm_config_target=${electron.version}
    node ../../node_modules/node-gyp/bin/node-gyp.js rebuild \
      --directory=../../node_modules/node-pty \
      --build-from-source \
      --runtime=electron \
      --target=${electron.version} \
      --nodedir=${electron.headers} \
      --disturl= \
      --offline

    # Keep node-gyp dependency files out of both the initially staged tree and
    # electron-builder's beforePack restaging pass. The native addon and the
    # Darwin spawn-helper remain in Release/.
    rm -rf ../../node_modules/node-pty/build/Release/{.deps,node-addon-api,obj.target}

    node scripts/stage-native-deps.mjs \
      --out "$TMPDIR/native-deps" --platform ${targetPlatform} --arch ${targetArch}
    node ../../scripts/build/desktop.mjs \
      --source "$PWD/../.." --out "$PWD/dist" --icons "$PWD/../.." \
      --stamp ${hermes-agent.installStamp} --native-deps "$TMPDIR/native-deps" \
      --platform ${targetPlatform} --typecheck

    ${lib.optionalString isDarwin ''
      # Finder does not run the command-line wrapper and supplies only a small
      # PATH. Bake Nix defaults into the main bundle while still allowing an
      # explicit backend override from the launch environment.
      {
        printf '%s\n' \
          'process.env.HERMES_DESKTOP_HERMES ||= ${builtins.toJSON hermesExecutable};' \
          'process.env.PATH = ${builtins.toJSON runtimePath} + (process.env.PATH ? ":" + process.env.PATH : "");'
        cat dist/electron-main.mjs
      } > dist/electron-main.mjs.nix
      mv dist/electron-main.mjs.nix dist/electron-main.mjs
    ''}

    ${lib.optionalString isDarwin ''
      # electron-builder's extraResources are required at runtime.
      cp ${hermes-agent.installStamp} build/install-stamp.json

      # electron-builder mutates Electron.app while applying the Hermes bundle
      # identity, so copy nixpkgs' pinned dist to a writable build directory.
      # Supplying electronDist and disabling npm rebuild/download paths keeps
      # packaging fully offline; node-pty was already built for this runtime.
      rm -rf electron-dist
      mkdir electron-dist
      cp -R ${electron.dist}/. electron-dist/
      chmod -R u+w electron-dist
      export CSC_IDENTITY_AUTO_DISCOVERY=false

      # Upstream's run-electron-builder.mjs downloads Electron first.
      HERMES_PREPARED_NATIVE_DEPS="$TMPDIR/native-deps" \
      node ../../node_modules/electron-builder/cli.js \
        --config electron-builder.config.cjs \
        --publish never \
        -c.electronDist="$PWD/electron-dist" \
        -c.electronVersion=${electron.version} \
        -c.extraMetadata.version=${hermes-agent.version} \
        -c.mac.sign=null \
        -c.mac.notarize=false \
        --dir --mac --arm64
    ''}

    popd

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    app=apps/desktop/dist
    test -f "$app/index.html"
    test -f "$app/electron-main.mjs"
    test -f "$app/electron-preload.js"
    test -f "$app/node_modules/node-pty/package.json"

    pty_node=$(find "$app/node_modules/node-pty" -name '*.node' -print -quit)
    test -n "$pty_node"

    spawn_helper=$(find "$app/node_modules/node-pty" -name spawn-helper -print -quit)
    if [[ -n "$spawn_helper" ]]; then
      test -x "$spawn_helper"
    fi

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    ${lib.optionalString isLinux ''
      appDir=$out/share/hermes-desktop
      mkdir -p "$appDir" $out/bin
      cp -r apps/desktop/dist "$appDir/"
      # The sources only carry a 0.0.0 placeholder version.
      substitute apps/desktop/package.json "$appDir/package.json" \
        --replace-fail '"version": "0.0.0"' '"version": "${hermes-agent.version}"'

      cp ${hermes-agent.installStamp} "$appDir/install-stamp.json"

      # External Electron points process.resourcesPath at its own installation.
      substituteInPlace "$appDir/dist/electron-main.mjs" \
        --replace-fail process.resourcesPath "'$appDir'"

      makeWrapper ${lib.getExe electron} $out/bin/hermes-desktop \
        --add-flags "$appDir" \
        --set HERMES_DESKTOP_HERMES ${lib.escapeShellArg hermesExecutable} \
        --set ELECTRON_IS_DEV 0 \
        --prefix PATH : ${runtimePath}

      sourceIcon="$out/share/icons/hicolor/1024x1024/apps/hermes-desktop.png"
      install -Dm644 apps/desktop/assets/icon.png \
        "$sourceIcon"
      for size in 256 512; do
        install -d "$out/share/icons/hicolor/''${size}x''${size}/apps"
        gdk-pixbuf-thumbnailer -s "$size" "$sourceIcon" \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/hermes-desktop.png"
      done
    ''}

    ${lib.optionalString isDarwin ''
      mapfile -t builtApps < <(find apps/desktop/release -type d -name Hermes.app -prune -print)
      if [[ "''${#builtApps[@]}" -ne 1 ]]; then
        echo "error: expected exactly one electron-builder Hermes.app, found ''${#builtApps[@]}" >&2
        printf '  %s\n' "''${builtApps[@]}" >&2
        exit 1
      fi

      mkdir -p $out/Applications $out/bin
      cp -R "''${builtApps[0]}" $out/Applications/Hermes.app

      # Finder bypasses this terminal entry point, so launch defaults are
      # embedded in electron-main.mjs.
      makeWrapper "$out/Applications/Hermes.app/Contents/MacOS/Hermes" \
        $out/bin/hermes-desktop
    ''}

    runHook postInstall
  '';

  desktopItems = lib.optionals isLinux [
    (makeDesktopItem {
      name = "hermes-desktop";
      desktopName = "Hermes";
      comment = "Native desktop shell for Hermes Agent";
      exec = "hermes-desktop %U";
      icon = "hermes-desktop";
      categories = [ "Development" ];
      mimeTypes = [ "x-scheme-handler/hermes" ];
      startupWMClass = "hermes";
    })
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x $out/bin/hermes-desktop

    ${lib.optionalString isLinux ''
      appDir=$out/share/hermes-desktop
      ptyRoot="$appDir/dist/node_modules/node-pty"
      electronExecutable=${lib.getExe electron}

      test -f "$appDir/dist/index.html"
      test -f "$appDir/dist/electron-main.mjs"
      test -f "$appDir/dist/electron-preload.js"
      test -f "$appDir/install-stamp.json"
      test "$(node -p "require('$appDir/package.json').version")" = ${hermes-agent.version}
      grep -q HERMES_DESKTOP_HERMES $out/bin/hermes-desktop
      grep -q ${lib.escapeShellArg hermesExecutable} $out/bin/hermes-desktop

      pty_node=$(find "$ptyRoot" -name '*.node' -print -quit)
      test -n "$pty_node"
      if ldd "$pty_node" | grep -q 'not found'; then
        ldd "$pty_node" >&2
        exit 1
      fi

      test -f $out/share/applications/hermes-desktop.desktop
    ''}

    ${lib.optionalString isDarwin ''
      app=$out/Applications/Hermes.app
      resources="$app/Contents/Resources"
      ptyRoot="$resources/app.asar.unpacked/dist/node_modules/node-pty"
      electronExecutable="$app/Contents/MacOS/Hermes"

      test -x "$electronExecutable"
      test -f "$app/Contents/Info.plist"
      plutil -lint "$app/Contents/Info.plist"
      grep -a -q '<string>com.nousresearch.hermes</string>' "$app/Contents/Info.plist"
      grep -a -q '<string>hermes</string>' "$app/Contents/Info.plist"
      grep -a -q '<key>NSMicrophoneUsageDescription</key>' "$app/Contents/Info.plist"
      bundleIcon=$(find "$resources" -maxdepth 1 -name '*.icns' -print -quit)
      test -n "$bundleIcon"
      file "$bundleIcon" | grep -Eq 'Mac OS X icon|Apple Icon Image'
      test -f "$resources/app.asar"
      test -f "$resources/install-stamp.json"
      test -f "$resources/icon.ico"
      test -f "$ptyRoot/package.json"
      test -f "$resources/app.asar.unpacked/dist/electron-main.mjs"
      grep -q ${lib.escapeShellArg hermesExecutable} \
        "$resources/app.asar.unpacked/dist/electron-main.mjs"
      grep -q ${lib.escapeShellArg runtimePath} \
        "$resources/app.asar.unpacked/dist/electron-main.mjs"

      file "$electronExecutable" | grep -Eq 'Mach-O.*arm64'
      pty_node=$(find "$ptyRoot" -name '*.node' -print -quit)
      test -n "$pty_node"
      file "$pty_node" | grep -Eq 'Mach-O.*arm64'
      spawn_helper=$(find "$ptyRoot" -name spawn-helper -print -quit)
      test -n "$spawn_helper"
      test -x "$spawn_helper"
      file "$spawn_helper" | grep -Eq 'Mach-O.*arm64'
    ''}

    # Loading verifies the compiled addon against the exact packaged Electron
    # ABI; spawning a PTY also exercises the macOS spawn-helper when applicable.
    HERMES_PTY_MODULE="$ptyRoot" \
      HERMES_PTY_SHELL=${stdenv.shell} \
      ELECTRON_RUN_AS_NODE=1 \
      "$electronExecutable" ${./pty-smoke.cjs}

    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Assistants";
    inherit electron;
  };

  meta = with lib; {
    description = "Official native Electron desktop shell for Hermes Agent";
    homepage = "https://hermes-agent.nousresearch.com/";
    changelog = "https://github.com/NousResearch/hermes-agent/releases/tag/v${hermes-agent.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ aliez-ren ];
    mainProgram = "hermes-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
