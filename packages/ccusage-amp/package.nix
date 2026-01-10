{
  lib,
  stdenv,
  fetchzip,
  bun,
  flake,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation rec {
  pname = "ccusage-amp";
  version = "18.0.5";

  src = fetchzip {
    url = "https://registry.npmjs.org/@ccusage/amp/-/amp-${version}.tgz";
    hash = "sha256-2s7s/Y4ppDBVM0BJXc1c7yRXFACco8VYTopd2ej4898=";
  };

  nativeBuildInputs = [ bun ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    cp -r dist/* $out/bin/

    chmod +x $out/bin/index.js
    mv $out/bin/index.js $out/bin/ccusage-amp

    substituteInPlace $out/bin/ccusage-amp \
      --replace-fail "#!/usr/bin/env node" "#!${bun}/bin/bun"

    runHook postInstall
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  meta = with lib; {
    description = "Usage analysis tool for Amp CLI sessions";
    homepage = "https://github.com/ryoppippi/ccusage";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ryoppippi ];
    mainProgram = "ccusage-amp";
    platforms = platforms.all;
  };
}
