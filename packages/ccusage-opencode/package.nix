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
  pname = "ccusage-opencode";
  version = "18.0.5";

  src = fetchzip {
    url = "https://registry.npmjs.org/@ccusage/opencode/-/opencode-${version}.tgz";
    hash = "sha256-bHB6BHs1uTtgpt9Jww8rydBXVZK/9jrdpThI99aDC5I=";
  };

  nativeBuildInputs = [ bun ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    cp -r dist/* $out/bin/

    chmod +x $out/bin/index.js
    mv $out/bin/index.js $out/bin/ccusage-opencode

    substituteInPlace $out/bin/ccusage-opencode \
      --replace-fail "#!/usr/bin/env node" "#!${bun}/bin/bun"

    runHook postInstall
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  meta = with lib; {
    description = "Usage analysis tool for OpenCode sessions";
    homepage = "https://github.com/ryoppippi/ccusage";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ryoppippi ];
    mainProgram = "ccusage-opencode";
    platforms = platforms.all;
  };
}
