{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
  flake,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  pname = "cc-switch-cli";

in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/SaladDay/cc-switch-cli/releases/download/v${version}/cc-switch-cli-v${version}-linux-x64-musl.tar.gz";
    hash = hashes.x86_64-linux;
  };

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 cc-switch $out/bin/cc-switch

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/cc-switch";
  versionCheckProgramArg = "--version";

  passthru.category = "Claude Code Ecosystem";

  meta = with lib; {
    description = "CLI version of CC Switch - All-in-One Assistant for Claude Code, Codex & Gemini CLI";
    homepage = "https://github.com/SaladDay/cc-switch-cli";
    changelog = "https://github.com/SaladDay/cc-switch-cli/releases/tag/v${version}";
    downloadPage = "https://github.com/SaladDay/cc-switch-cli/releases";
    license = licenses.mit;
    maintainers = with flake.lib.maintainers; [ zrubing ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "cc-switch";
  };
}
