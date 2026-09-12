{
  lib,
  bashInteractive,
  buildNpmPackage,
  fetchurl,
  flake,
  jq,
  makeWrapper,
  nodejs,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version;

  # The npm tarball ships no lockfile, so vendor one alongside the source. The
  # lockfile is generated without devDependencies (see update.py), so the
  # manifest has to lose them too or npm re-resolves the whole tree:
  # devDependencies name @deepseek-ai/dsh-experimental-code-runtime-python,
  # which upstream never published, and `npm install --package-lock-only`
  # aborts on it with E404.
  srcWithLock = runCommand "dsh-source" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies)' $out/package.json > $out/package.json.tmp
    mv $out/package.json.tmp $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "dsh";
  inherit version;
  src = srcWithLock;

  npmDepsFetcherVersion = 2;
  npmDepsHash = versionData.npmDepsHash;

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # /bin/bash does not exist on NixOS (issue #8086)
    substituteInPlace \
      $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js \
      --replace-fail '"/bin/bash"' '"${lib.getExe bashInteractive}"'

    rm $out/bin/dsh
    makeWrapper ${lib.getExe nodejs} $out/bin/dsh \
      --argv0 dsh \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Open-source agent harness developed by DeepSeek AI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases";
    downloadPage = "https://www.npmjs.com/package/@deepseek-ai/dsh";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      fromSource
    ];
    maintainers = with flake.lib.maintainers; [ JachinShen ];
    mainProgram = "dsh";
    platforms = lib.platforms.all;
  };
}
