{
  mkUpdater,
  nodejs,
  buildNpmPackage,
  fetchurl,
  flake,
  git,
  jq,
  lib,
  makeWrapper,
  nodejs_22,
  python3,
  runCommand,
  stdenv,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version;

  # The npm tarball contains the built application but no lockfile. It is also
  # published from a workspace whose dev dependencies use workspace:*.
  srcWithLock = runCommand "bb-app-src-with-lock" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/bb-app/-/bb-app-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies)' $out/package.json > $out/package.json.tmp
    mv $out/package.json.tmp $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  # better-sqlite3's Statement destructor trips Node 24's
  # RemoveEnvironmentCleanupHook assertion when the host daemon's worker
  # thread shuts down, crashing `bb-app start`. Node 22 is unaffected and
  # within upstream's supported engine range.
  nodejs = nodejs_22;
  npmDepsFetcherVersion = 2;
  pname = "bb-app";
  inherit version;

  src = srcWithLock;
  npmDepsHash = versionData.npmDepsHash;
  makeCacheWritable = true;

  # The published package already contains the application, server, host
  # daemon, and web UI bundles.
  dontNpmBuild = true;

  # Install dependencies without running every lifecycle script, then compile
  # the native modules explicitly for Nix's Node.js and host platform.
  npmRebuildFlags = [ "--ignore-scripts" ];
  preBuild = ''
    npm_config_build_from_source=true \
      npm rebuild @parcel/watcher better-sqlite3 node-pty
  '';

  nativeBuildInputs = [
    makeWrapper
    python3
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  # Git is an upstream runtime prerequisite. Provider CLIs continue to resolve
  # from the user's PATH.
  postInstall = ''
    packageDir=$out/lib/node_modules/bb-app

    # Prefer the watcher built above over npm's platform-specific prebuilds,
    # which npmInstallHook restores while assembling the output.
    find "$packageDir/node_modules/@parcel" -mindepth 1 -maxdepth 1 \
      -type d -name 'watcher-*' -exec rm -rf {} +

    # Native build intermediates are not needed at runtime.
    rm -rf \
      "$packageDir/node_modules/@parcel/watcher/build/Release/obj.target" \
      "$packageDir/node_modules/better-sqlite3/build/Release/obj.target" \
      "$packageDir/node_modules/node-pty/build/Release/obj.target"

    for program in bb bb-app bb-host-daemon bb-server; do
      wrapProgram "$out/bin/$program" \
        --prefix PATH : ${lib.makeBinPath [ git ]}
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$TMPDIR
    $out/bin/bb-app --help | grep -q '^Usage:$'

    # The native modules rebuilt in preBuild must load with Nix's Node.js.
    export NODE_PATH=$out/lib/node_modules/bb-app/node_modules
    ${lib.getExe nodejs_22} -e \
      "require('@parcel/watcher'); require('better-sqlite3'); require('node-pty')"

    # bb refuses plugins whose host.js digest drifted (e.g. via patchShebangs, #8436)
    for meta in $out/lib/node_modules/bb-app/server/dist/builtin-plugins/*/dist/host.meta.json; do
      want=$(${lib.getExe jq} -r .artifactDigest "$meta")
      got=$(sha256sum "$(dirname "$meta")/host.js" | cut -d' ' -f1)
      [ "$want" = "$got" ] || { echo "digest mismatch for $meta"; exit 1; }
    done

    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  passthru.updater = mkUpdater {

    kind = "script";

    tools = [ nodejs ];

  };

  meta = {
    description = "Agentic IDE for orchestrating coding agents";
    homepage = "https://getbb.app";
    changelog = "https://getbb.app/changelog#${version}";
    downloadPage = "https://www.npmjs.com/package/bb-app";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ jvmncs ];
    mainProgram = "bb-app";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
