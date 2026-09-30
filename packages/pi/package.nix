{
  lib,
  buildNpmPackage,
  bun,
  fetchurl,
  fd,
  formatelf,
  libxcb,
  mkUpdater,
  rcodesign,
  ripgrep,
  runCommand,
  stdenv,
  versionCheckHook,
  versionCheckHomeHook,
  useBun ? true,
}:

let
  versionData = lib.importJSON ./hashes.json;
  version = versionData.version;
  nativeTargets = {
    aarch64-darwin = "darwin-arm64";
    aarch64-linux = "linux-arm64";
    x86_64-linux = "linux-x64";
  };
  nativeTarget =
    nativeTargets.${stdenv.hostPlatform.system}
      or (throw "Unsupported Pi platform: ${stdenv.hostPlatform.system}");
  nativePlatform = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
  nativeFile = "${nativePlatform}-platform${lib.optionalString stdenv.hostPlatform.isLinux "-x11"}.node";

  # Create a source with package-lock.json included
  srcWithLock = runCommand "pi-src-with-lock" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    rm -f $out/npm-shrinkwrap.json
    cp ${./package-lock.json} $out/package-lock.json
    # 0.85.0 imports pi-server without declaring it (earendil-works/pi#9132).
    sed -i '/"@earendil-works\/pi-protocol"/a\    "@earendil-works/pi-server": "^${version}",' $out/package.json
    grep -q pi-server $out/package.json
  '';
in
buildNpmPackage {
  npmDepsFetcherVersion = 2;
  inherit version;
  pname = "pi";

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  makeCacheWritable = true;

  # The package from npm is already built
  dontNpmBuild = true;

  nativeBuildInputs =
    lib.optional useBun bun
    ++ lib.optional (useBun && stdenv.hostPlatform.isLinux) formatelf
    ++ lib.optionals (useBun && stdenv.hostPlatform.isDarwin) [
      rcodesign
    ];

  buildInputs = lib.optional (useBun && stdenv.hostPlatform.isLinux) libxcb;

  # Compile a standalone binary like upstream's build:binary script. Running
  # dist/bun/cli.js directly with Bun breaks extension module aliasing (#6794).
  # Pi's standalone binary uses Bun, but the npm package also ships a Node
  # entry point. The Node mode is useful on older CPUs where Bun's binary
  # requires unsupported instruction sets.
  preInstall = lib.optionalString useBun ''
    # Upstream loads embedded workers by their src/ paths at runtime;
    # the npm tarball only ships dist/, so recreate their entrypoints.
    mkdir -p src/utils src/extensions/codemode src/modes src/core
    echo 'import "../../dist/utils/image-resize-worker.js";' > src/utils/image-resize-worker.ts
    echo 'import "../../../dist/extensions/codemode/worker.js";' > src/extensions/codemode/worker.ts
    ln -s ../../dist/modes/interactive src/modes/interactive
    ln -s ../../dist/core/export-html src/core/export-html

    bun build --compile \
      ./dist/bun/cli.js \
      ./src/utils/image-resize-worker.ts \
      ./src/extensions/codemode/worker.ts \
      --outfile dist/pi
  '';

  postInstall =
    if useBun then
      ''
        pkgdir=$out/libexec/pi

        # The binary embeds all modules; assemble the release layout that
        # upstream's scripts/build-binaries.sh ships.
        rm -rf "$out/lib" "$out/bin"
        mkdir -p "$out/bin" "$pkgdir/theme" "$pkgdir/assets"
        cp dist/pi "$pkgdir/"
        cp package.json README.md CHANGELOG.md "$pkgdir/"
        # Mirror scripts/build-binaries.sh: Bun cannot embed these runtime assets.
        mkdir -p "$pkgdir/native/${nativePlatform}/prebuilds"
        cp -r node_modules/@earendil-works/pi-tui/native/${nativePlatform}/prebuilds/${nativeTarget} \
          "$pkgdir/native/${nativePlatform}/prebuilds/"
        cp node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm "$pkgdir/"
        cp dist/modes/interactive/theme/*.json "$pkgdir/theme/"
        cp dist/modes/interactive/assets/* "$pkgdir/assets/"
        cp -r dist/core/export-html "$pkgdir/"
        cp -r docs examples "$pkgdir/"
        # Keep patchShebangs from pulling Node into the closure via shipped scripts.
        find "$pkgdir" -name '*.js' -exec chmod -x {} +

        makeWrapper "$pkgdir/pi" "$out/bin/pi" \
          --prefix PATH : ${
            lib.makeBinPath [
              fd
              ripgrep
            ]
          } \
          --set PI_PACKAGE_DIR "$pkgdir" \
          --set PI_SKIP_VERSION_CHECK 1 \
          --set PI_TELEMETRY 0
      ''
    else
      ''
        wrapProgram "$out/bin/pi" \
          --prefix PATH : ${
            lib.makeBinPath [
              fd
              ripgrep
            ]
          } \
          --set PI_SKIP_VERSION_CHECK 1 \
          --set PI_TELEMETRY 0
      '';

  # Re-sign the bun-compiled binary after fixup, following the amp pattern.
  # fixDarwinDylibNames may run install_name_tool which invalidates the
  # signature; bun's embedded code-signing can also produce invalid
  # signatures on newer macOS versions.
  postFixup = lib.optionalString (useBun && stdenv.hostPlatform.isDarwin) ''
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed $out/libexec/pi/pi
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postInstallCheck = lib.optionalString useBun ''
    ${bun}/bin/bun --eval 'require(process.argv[1])' \
      "$out/libexec/pi/native/${nativePlatform}/prebuilds/${nativeTarget}/${nativeFile}"
  '';

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/%40earendil-works/pi-coding-agent";
  };

  meta = {
    description = "A terminal-based coding agent with multi-model support";
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with lib.maintainers; [ aos ];
    platforms = if useBun then builtins.attrNames nativeTargets else lib.platforms.all;
    mainProgram = "pi";
  };
}
