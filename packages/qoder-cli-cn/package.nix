{
  lib,
  flake,
  stdenv,
  fetchurl,
  wrapBuddy,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version platforms;

  platform = stdenv.hostPlatform.system;
  src = platforms.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "qoder-cli-cn";
  inherit version;

  src = fetchurl {
    inherit (src) url hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  sourceRoot = ".";

  dontStrip = true; # do not mess with the bun runtime

  installPhase = ''
    runHook preInstall

    install -Dm755 qoderclicn $out/bin/qoderclicn

    runHook postInstall
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "终端原生的 AI 编程搭档，也是可被集成的智能体引擎。";
    homepage = "https://qoder.cn";
    changelog = "https://qoder.cn/changelog";
    downloadPage = "https://qoder.cn/download";
    license = flake.lib.licenses.unfree;
    maintainers = with maintainers; [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "qoderclicn";
  };
}
