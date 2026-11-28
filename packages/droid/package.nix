{
  mkUpdater,
  lib,
  flake,
  stdenv,
  fetchurl,
  makeWrapper,
  wrapBuddy,
  gcc-unwrapped,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version;

  platformMap = {
    x86_64-linux = "linux/x64";
    aarch64-linux = "linux/arm64";
    aarch64-darwin = "darwin/arm64";
  };

  platform = stdenv.hostPlatform.system;
  platformPath = platformMap.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "droid";
  inherit version;

  src = fetchurl {
    url = "https://downloads.factory.ai/factory-cli/releases/${version}/${platformPath}/droid";
    hash = versionData.droid.${platform};
  };

  rgSrc = fetchurl {
    url = "https://downloads.factory.ai/ripgrep/${platformPath}/rg";
    hash = versionData.ripgrep.${platform};
  };

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    wrapBuddy
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gcc-unwrapped.lib
  ];

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/lib/factory

    # Install the main droid binary
    install -Dm755 $src $out/bin/droid

    # Install ripgrep for code search functionality
    install -Dm755 $rgSrc $out/lib/factory/rg

    # Wrap droid to ensure ripgrep is in PATH
    wrapProgram $out/bin/droid \
      --prefix PATH : $out/lib/factory

    runHook postInstall
  '';

  doInstallCheck = true;
  # 0.104.0 unconditionally creates ~/.factory at startup before parsing
  # --version, so the empty-env version check needs a writable HOME.
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  passthru.updater = mkUpdater { kind = "script"; };

  meta = with lib; {
    description = "Factory AI's Droid - AI-powered development agent for your terminal";
    homepage = "https://factory.ai";
    changelog = "https://docs.factory.ai/changelog/cli-updates";
    downloadPage = "https://factory.ai/product/ide";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ ];
    mainProgram = "droid";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
