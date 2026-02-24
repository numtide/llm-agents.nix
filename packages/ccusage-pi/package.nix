{
  lib,
  stdenv,
  fetchzip,
  bun,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation rec {
  pname = "ccusage-pi";
  version = "18.0.6";

  src = fetchzip {
    url = "https://registry.npmjs.org/@ccusage/pi/-/pi-${version}.tgz";
    hash = "sha256-r81UVEiFCu3xc/RRoTxlif7cNeerY6dp7bMpDkeuXNM=";
  };

  nativeBuildInputs = [ bun ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    cp -r dist/* $out/bin/

    chmod +x $out/bin/index.js
    mv $out/bin/index.js $out/bin/ccusage-pi

    substituteInPlace $out/bin/ccusage-pi \
      --replace-fail "#!/usr/bin/env node" "#!${bun}/bin/bun"

    runHook postInstall
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Usage Analytics";

  meta = with lib; {
    description = "Pi-agent usage tracking for Claude Max";
    homepage = "https://github.com/ryoppippi/ccusage";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with maintainers; [ ryoppippi ];
    mainProgram = "ccusage-pi";
    platforms = platforms.all;
  };
}
