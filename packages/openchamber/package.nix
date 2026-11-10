{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  git,
  jq,
  mkUpdater,
  opencode2,
  ripgrep,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version;

  # The npm tarball ships a prebuilt UI but no lockfile. The vendored lock
  # omits devDependencies and scripts (prepack needs the monorepo).
  srcWithLock = runCommand "openchamber-src-with-lock" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies) | del(.scripts)' $out/package.json > $out/package.json.tmp
    mv $out/package.json.tmp $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "openchamber";
  inherit version;

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  npmDepsFetcherVersion = 2;

  # Native addons ship prebuilds; their install scripts would compile online.
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  dontNpmBuild = true;

  makeWrapperArgs = [
    # requires OpenCode 2.x
    "--set-default OPENCODE_BINARY ${lib.getExe opencode2}"
    "--prefix PATH : ${
      lib.makeBinPath [
        git
        ripgrep
      ]
    }"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/%40openchamber/web";
    stripDevDependencies = true;
  };

  meta = {
    description = "Web and desktop UI for the OpenCode AI coding agent";
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ dxops ];
    mainProgram = "openchamber";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
