{
  lib,
  flake,
  mkUpdater,
  stdenv,
  platformSource,
  unzip,
  wrapBuddy,
  libsecret,
  versionCheckHook,
  versionCheckHomeHook,
  codesignCheckHook,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    };
    urlTemplate = "https://cli.coderabbit.ai/releases/{version}/coderabbit-{platform}.zip";
  };
in
stdenv.mkDerivation {
  pname = "coderabbit-cli";
  inherit (source) version src;

  nativeBuildInputs = [ unzip ] ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libsecret ];

  unpackPhase = ''
    unzip $src
  '';

  dontStrip = true; # to no mess with the bun runtime

  installPhase = ''
    runHook preInstall

    install -Dm755 coderabbit $out/bin/coderabbit
    ln -s $out/bin/coderabbit $out/bin/cr

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
    codesignCheckHook
  ];
  versionCheckProgramArg = [ "--version" ];
  codesignTeamId = "47UZS55279";
  codesignSources = source.darwinSrcs;

  passthru.category = "Code Review";
  passthru.updater = mkUpdater (
    source.updater
    // {
      versionSource = {
        type = "text";
        url = "https://cli.coderabbit.ai/releases/latest/VERSION";
      };
    }
  );

  meta = with lib; {
    description = "AI-powered code review CLI tool";
    homepage = "https://coderabbit.ai";
    changelog = "https://docs.coderabbit.ai/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = source.platforms;
    mainProgram = "coderabbit";
  };
}
