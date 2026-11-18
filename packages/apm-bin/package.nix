{
  lib,
  flake,
  stdenv,
  fetchurl,
  formatelf,
  zlib,
  mkUpdater,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  platformMap = {
    x86_64-linux = "linux-x86_64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };

  platform = stdenv.hostPlatform.system;
  platformSuffix = platformMap.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "apm-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/microsoft/apm/releases/download/v${version}/apm-${platformSuffix}.tar.gz";
    hash = hashes.${platform};
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ zlib ];

  # PyInstaller bundle: the bootloader and _internal must stay together.
  dontStrip = true;

  unpackPhase = "tar -xzf $src --strip-components=1";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -a apm _internal $out/bin/

    runHook postInstall
  '';

  # `apm --version` imports GitPython, which insists on finding a git
  # executable. Running the check would either pull git (and its Python/Perl
  # deps) into the runtime closure or require a build-only wrapper. The
  # release is pinned by hashes.json, so skip the install check.
  doInstallCheck = false;

  passthru.category = "Utilities";

  passthru.updater = mkUpdater {
    kind = "platform";
    versionSource = {
      type = "github";
      owner = "microsoft";
      repo = "apm";
    };
    urlTemplate = "https://github.com/microsoft/apm/releases/download/v{version}/apm-{platform}.tar.gz";
    platforms = platformMap;
  };

  meta = with lib; {
    description = "Agent Package Manager (official standalone release)";
    homepage = "https://github.com/microsoft/apm";
    changelog = "https://github.com/microsoft/apm/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ xbpk3t ];
    mainProgram = "apm";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
