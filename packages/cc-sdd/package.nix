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
  pname = "cc-sdd";
  version = "2.0.5";

  src = fetchzip {
    url = "https://registry.npmjs.org/cc-sdd/-/cc-sdd-${version}.tgz";
    hash = "sha256-4wQVFEWh7TIXnQDxd/2RFLqxRJ1QsG0n9LrUkczMy58=";
  };

  nativeBuildInputs = [ bun ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/cc-sdd/dist

    cp -r dist/* $out/lib/cc-sdd/dist/
    cp -r templates $out/lib/cc-sdd/
    cp package.json $out/lib/cc-sdd/

    chmod +x $out/lib/cc-sdd/dist/cli.js

    substituteInPlace $out/lib/cc-sdd/dist/cli.js \
      --replace-fail "#!/usr/bin/env node" "#!${bun}/bin/bun"

    ln -s $out/lib/cc-sdd/dist/cli.js $out/bin/cc-sdd

    runHook postInstall
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  meta = with lib; {
    description = "Spec-driven development framework for AI coding agents";
    homepage = "https://github.com/gotalab/cc-sdd";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ryoppippi ];
    mainProgram = "cc-sdd";
    platforms = platforms.all;
  };
}
