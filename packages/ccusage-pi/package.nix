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
  pname = "ccusage-pi";
  version = "18.0.5";

  src = fetchzip {
    url = "https://registry.npmjs.org/@ccusage/pi/-/pi-${version}.tgz";
    hash = "sha256-8QKNXMjzi+TwlygXvL5W1H5oyk0cJXsXl5jh5j+HQ14=";
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

  meta = with lib; {
    description = "Pi-agent usage tracking for Claude Max";
    homepage = "https://github.com/ryoppippi/ccusage";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ryoppippi ];
    mainProgram = "ccusage-pi";
    platforms = platforms.all;
  };
}
