{
  lib,
  buildNpmPackage,
  fetchurl,
  flake,
  mkUpdater,
  node-gyp,
  nodejs,
  python3,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  version = versionData.version;
  # Create a source with package-lock.json included
  srcWithLock = runCommand "minimax-code-src-with-lock" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@minimax-ai/code/-/code-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  npmDepsFetcherVersion = 2;
  pname = "minimax-code";
  inherit version;
  inherit nodejs;

  src = srcWithLock;

  nativeBuildInputs = [
    node-gyp
    python3
  ];

  npmDepsHash = versionData.npmDepsHash;

  NPM_CONFIG_IGNORE_SCRIPTS = "true";

  dontNpmBuild = true;

  postInstall = ''
    pushd $out/lib/node_modules/@minimax-ai/code/node_modules/better-sqlite3
    node-gyp rebuild --nodedir=${nodejs}
    find build -mindepth 1 -maxdepth 1 ! -name Release -exec rm -rf {} +
    find build/Release -mindepth 1 ! -name '*.node' -exec rm -rf {} +
    popd
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/%40minimax-ai/code";
  };

  meta = {
    description = "An open-source coding agent for your terminal, powered by MiniMax.";
    homepage = "https://github.com/MiniMax-AI/minimax-code";
    changelog = "https://www.npmjs.com/package/@minimax-ai/code/v/${version}";
    downloadPage = "https://www.npmjs.com/package/@minimax-ai/code?activeTab=versions";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ _74k1 ];
    mainProgram = "mcode";
    platforms = lib.platforms.unix;
  };
}
