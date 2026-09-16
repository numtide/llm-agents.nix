{
  lib,
  flake,
  stdenv,
  fetchurl,
  formatelf,
  versionCheckHook,
  versionCheckHomeHook,
  codesignCheckHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version urls hashes;

  platform = stdenv.hostPlatform.system;

  srcFor =
    system:
    fetchurl {
      url = urls.${system} or (throw "Unsupported system: ${system}");
      hash = hashes.${system} or (throw "Unsupported system: ${system}");
    };
in
stdenv.mkDerivation {
  pname = "antigravity-cli";
  inherit version;

  src = srcFor platform;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    (lib.getLib stdenv.cc.cc)
  ];

  dontStrip = true;

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 antigravity $out/bin/agy

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHomeHook
    codesignCheckHook
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isLinux) [ versionCheckHook ];
  codesignTeamId = "EQHXZ8M8AV";
  codesignSources = [ (srcFor "aarch64-darwin") ];

  installCheckPhase = lib.optionalString stdenv.hostPlatform.isLinux ''
    runHook preInstallCheck

    $out/bin/agy --help >/dev/null

    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "CLI for Google Antigravity, an agentic development platform";
    homepage = "https://antigravity.google/";
    changelog = "https://antigravity.google/cli";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ ryoppippi ];
    mainProgram = "agy";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
