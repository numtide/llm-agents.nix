{
  lib,
  stdenv,
  fetchzip,
  bun,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation rec {
  pname = "ccusage-opencode";
  version = "18.0.8";

  src = fetchzip {
    url = "https://registry.npmjs.org/@ccusage/opencode/-/opencode-${version}.tgz";
    hash = "sha256-6V4Wd08KvEy7XvEsPkWNFGiGpTGRyS5GHyIav6yKlBE=";
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

  passthru.category = "Usage Analytics";

  meta = with lib; {
    description = "Usage analysis tool for OpenCode sessions";
    homepage = "https://github.com/ryoppippi/ccusage";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with maintainers; [ ryoppippi ];
    mainProgram = "ccusage-opencode";
    platforms = platforms.all;
  };
}
