{
  lib,
  flake,
  mkUpdater,
  stdenv,
  fetchurl,
  wrapBuddy,
  versionCheckHook,
  versionCheckHomeHook,
  codesignCheckHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version platforms;

  srcFor =
    system:
    fetchurl {
      inherit (platforms.${system} or (throw "Unsupported system: ${system}")) url hash;
    };
in
stdenv.mkDerivation {
  pname = "qoder-cli";
  inherit version;

  src = srcFor stdenv.hostPlatform.system;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  sourceRoot = ".";

  dontStrip = true; # do not mess with the bun runtime

  installPhase = ''
    runHook preInstall

    install -Dm755 qodercli $out/bin/qodercli

    runHook postInstall
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
    codesignCheckHook
  ];
  codesignTeamId = "T27K5A5ZWD";
  codesignSources = [ (srcFor "aarch64-darwin") ];

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "manifest";
    manifestUrl = "https://qoder-ide.oss-ap-southeast-1.aliyuncs.com/qodercli/channels/manifest.json";
    platformMap = [
      {
        os = "linux";
        arch = "amd64";
        platform = "x86_64-linux";
      }
      {
        os = "linux";
        arch = "arm64";
        platform = "aarch64-linux";
      }
      {
        os = "darwin";
        arch = "arm64";
        platform = "aarch64-darwin";
      }
    ];
  };

  meta = with lib; {
    description = "Qoder AI CLI tool - Terminal-based AI assistant for code development";
    homepage = "https://qoder.com";
    changelog = "https://qoder.com/changelog";
    downloadPage = "https://qoder.com/download";
    license = flake.lib.licenses.unfree;
    maintainers = with maintainers; [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "qodercli";
  };
}
