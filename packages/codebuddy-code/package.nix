{
  lib,
  buildNpmPackage,
  fetchurl,
  mkUpdater,
  nodejs,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  version = versionData.version;
  srcWithLock = runCommand "codebuddy-code-src-with-lock" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@tencent-ai/codebuddy-code/-/codebuddy-code-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "codebuddy-code";
  inherit version;
  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  npmDepsFetcherVersion = 2;

  # The published tarball is already bundled; skip install scripts.
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  # patchShebangs leaves `#!/usr/bin/env -S node <flags>` alone
  postInstall = ''
    substituteInPlace $out/lib/node_modules/@tencent-ai/codebuddy-code/bin/codebuddy-lowmem \
      --replace-fail "#!/usr/bin/env -S node" "#!${lib.getExe nodejs}"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgram = "${placeholder "out"}/bin/codebuddy";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/%40tencent-ai/codebuddy-code";
  };

  meta = {
    description = "Tencent's AI coding agent for the terminal";
    homepage = "https://www.codebuddy.ai/cli";
    changelog = "https://www.npmjs.com/package/@tencent-ai/codebuddy-code/v/${version}";
    downloadPage = "https://www.npmjs.com/package/@tencent-ai/codebuddy-code?activeTab=versions";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    maintainers = [ ];
    mainProgram = "codebuddy";
    platforms = lib.platforms.unix;
  };
}
