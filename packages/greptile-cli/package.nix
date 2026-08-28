{
  lib,
  mkUpdater,
  stdenv,
  platformSource,
  makeWrapper,
  nodejs,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "greptile.js";
      aarch64-linux = "greptile.js";
      aarch64-darwin = "greptile.js";
    };
    urlTemplate = "https://github.com/greptileai/cli/releases/download/v{version}/{platform}";
  };
in
stdenv.mkDerivation {
  pname = "greptile-cli";
  inherit (source) version src;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm644 $src $out/libexec/greptile.js
    makeWrapper ${lib.getExe nodejs} $out/bin/greptile \
      --add-flags $out/libexec/greptile.js

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Code Review";
  passthru.updater = mkUpdater (
    source.updater
    // {
      versionSource = {
        type = "github";
        owner = "greptileai";
        repo = "cli";
      };
    }
  );

  meta = with lib; {
    description = "Greptile code review from your terminal";
    homepage = "https://www.greptile.com/cli";
    changelog = "https://github.com/greptileai/cli/releases/tag/v${source.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryBytecode ];
    mainProgram = "greptile";
    platforms = source.platforms;
  };
}
